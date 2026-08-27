"""Adaptador para LaLiga Fantasy (Relevo, antes Marca).

La API oficial no documentada (`api-fantasy.llt-services.com`) lleva caída
—502 de Azure Application Gateway, verificado con curl y con navegador real,
con y sin cabeceras de la app oficial— desde que se investigó por primera
vez este adaptador. En vez de depender de que LALIGA arregle su backend,
`get_all_players()` y `get_player_price_history()` sacan los datos de
`futbolfantasy.com`, un sitio de estadísticas de fantasy que sí tiene el
mercado actualizado (verificado: su "última actualización" es de horas
antes de escribir esto, no datos congelados).

Su tabla de mercado viene enteramente renderizada en el HTML servido por el
servidor — sin JavaScript de por medio — con cada fila `<tr>` llevando el id,
nombre, posición, precio actual **y precios de hace 1/2/3/7/14/30 días**
como atributos `data-*`. Eso nos da precio actual e histórico en una sola
petición, sin necesitar un navegador headless ni pegar 670 peticiones (una
por jugador). `robots.txt` de futbolfantasy.com es permisivo (`Disallow:`
vacío) y esto hace como mucho una petición cada 3h — tráfico mínimo.

# TODO: si LALIGA arregla su API oficial, sería más correcto volver a ella
# en vez de depender del HTML de un tercero (más frágil: se rompe si
# cambian las clases/atributos de su tabla).

Cobertura:
- get_all_players(): sí, vía scraping de futbolfantasy.com.
- get_player_price_history(): sí, histórico de 30 días de la misma tabla.
- get_player_points_history(): sí, desglose real jornada a jornada. La
  página `/analytics/laliga-fantasy/puntos` abre, por jugador, un modal con
  el detalle partido a partido (`/analytics/stats/detalle/{id}/{temporada}`)
  cuyas filas llevan `data-jornada="J2"` y `data-puntos='{"laliga-fantasy":
  24, ...}'` — el mismo JSON con puntos según el modo de puntuación que
  vemos en la web, del que solo nos interesa la clave "laliga-fantasy". Eso
  es una petición extra por jugador (no viene en el listado general), así
  que sync_data la hace una vez por jugador y sincronización (~670
  peticiones cada 3h, ~0.1s cada una vía requests normal, sin login ni JS).
- login() / get_user_team(): sin implementar a propósito — requieren ROPC
  contra un tenant B2C de Azure AD, no una API key, y sigue sin resolverse
  la decisión consciente de si merece la pena perseguir eso (ver TODO
  histórico más abajo).
"""
from __future__ import annotations

import datetime as dt
import json
import logging
import re
import time

import requests
from bs4 import BeautifulSoup
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from fantasy_assistant.datasources.base import (
    AuthSession,
    FantasyDataSource,
    Player,
    PointsEntry,
    PricePoint,
    RivalAnalysis,
    Team,
)

logger = logging.getLogger(__name__)

MARKET_URL = "https://www.futbolfantasy.com/analytics/laliga-fantasy/mercado"
PUNTOS_URL = "https://www.futbolfantasy.com/analytics/laliga-fantasy/puntos"
DETALLE_URL = "https://www.futbolfantasy.com/analytics/stats/detalle/{player_id}/{temporada}"

_ONCLICK_ID_RE = re.compile(r"openPlayerPointsStats\((\d+)")
# La propia página /puntos hardcodea el id de temporada en su JS
# (`'/analytics/stats/detalle/' + id + '/2027?...'`) — lo extraemos de ahí
# en vez de hardcodearlo aquí, para no romper cuando cambie de temporada.
_TEMPORADA_RE = re.compile(r"/analytics/stats/detalle/'\s*\+\s*id\s*\+\s*'/(\d+)")
_JORNADA_NUM_RE = re.compile(r"\d+")

POSITION_MAP_ES = {
    "Portero": "POR",
    "Defensa": "DEF",
    "Mediocampista": "MED",
    "Delantero": "DEL",
}

# data-valorN = precio hace N días (aproximado a partir de hoy).
HISTORIAL_DIAS = (1, 2, 3, 7, 14, 30)

# get_player_points_history() hace una petición por jugador (no viene en el
# listado general) — este margen entre peticiones evita 429 de su
# rate-limiting (verificado: en ráfaga sin pausa nos bloqueó en ~40
# peticiones). Con ~670 jugadores, una sincronización tarda unos 4-5 min de
# más por esto — aceptable para un job que corre en background cada 3h.
JORNADAS_THROTTLE_SECONDS = 0.4

SOURCE_NAME = "laligafantasy"


class LaLigaFantasyAdapter(FantasyDataSource):
    def __init__(self, session: requests.Session | None = None) -> None:
        self._http = session or requests.Session()
        self._http.headers.update({"User-Agent": "Mozilla/5.0 (fantasy-assistant)"})
        # Caché del último scrape del mercado, para no repetir la petición
        # una vez por jugador al pedir el histórico justo después de
        # get_all_players() (patrón habitual en jobs/sync_data.py).
        self._market_cache: dict[str, dict] = {}
        self._puntos_cache: dict[str, dict] = {}
        self._temporada_id: str | None = None

    @retry(
        reraise=True,
        stop=stop_after_attempt(4),
        wait=wait_exponential(multiplier=1, min=1, max=20),
        retry=retry_if_exception_type((requests.ConnectionError, requests.Timeout, requests.HTTPError)),
    )
    def _fetch_market(self) -> dict[str, dict]:
        resp = self._http.get(MARKET_URL, timeout=20)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")

        jugadores: dict[str, dict] = {}
        for row in soup.select("tr[data-id]"):
            player_id = row.get("data-id")
            if not player_id:
                continue

            nombre_el = row.select_one(".player-info span") or row.select_one(".player-info")
            equipo_el = row.select_one(".player-equipo")

            jugadores[player_id] = {
                "id": player_id,
                "nombre": (nombre_el.get_text(strip=True) if nombre_el else row.get("data-nombre", "")),
                "equipo": equipo_el.get_text(strip=True) if equipo_el else "",
                "posicion_raw": row.get("data-posicion", ""),
                "valor": row.get("data-valor"),
                **{f"valor{d}": row.get(f"data-valor{d}") for d in HISTORIAL_DIAS},
            }

        self._market_cache = jugadores
        return jugadores

    @retry(
        reraise=True,
        stop=stop_after_attempt(4),
        wait=wait_exponential(multiplier=1, min=1, max=20),
        retry=retry_if_exception_type((requests.ConnectionError, requests.Timeout, requests.HTTPError)),
    )
    def _fetch_puntos(self) -> dict[str, dict]:
        resp = self._http.get(PUNTOS_URL, timeout=20)
        resp.raise_for_status()

        temporada_match = _TEMPORADA_RE.search(resp.text)
        if temporada_match:
            self._temporada_id = temporada_match.group(1)

        soup = BeautifulSoup(resp.text, "html.parser")

        jugadores: dict[str, dict] = {}
        for row in soup.select("tr.elemento_jugador[data-nombre]"):
            match = _ONCLICK_ID_RE.search(row.get("onclick", ""))
            if not match:
                continue
            player_id = match.group(1)
            rival_el = row.select_one(".rival-probability")
            jugadores[player_id] = {
                "media3": row.get("data-media3"),
                "media5": row.get("data-media5"),
                "puntostemporada": row.get("data-puntostemporada"),
                # title="Jornada 3 · Próximo rival: Elche (Casa)" — nos quedamos
                # solo con la parte de después de "Próximo rival: ".
                "proximo_rival": (rival_el.get("title", "").split("Próximo rival: ", 1)[-1] if rival_el else ""),
            }

        self._puntos_cache = jugadores
        return jugadores

    @retry(
        reraise=True,
        stop=stop_after_attempt(4),
        wait=wait_exponential(multiplier=1, min=1, max=20),
        retry=retry_if_exception_type((requests.ConnectionError, requests.Timeout, requests.HTTPError)),
    )
    def _fetch_jornadas(self, player_id: str) -> list[PointsEntry]:
        if not self._temporada_id:
            self._fetch_puntos()
        if not self._temporada_id:
            return []

        time.sleep(JORNADAS_THROTTLE_SECONDS)
        url = DETALLE_URL.format(player_id=player_id, temporada=self._temporada_id)
        resp = self._http.get(url, params={"stat": "puntuacion"}, timeout=20)
        if resp.status_code == 404:
            # Algunos ids del mercado (ej. entrenadores) no tienen ficha de
            # stats — no es un fallo transitorio, no tiene sentido reintentar.
            return []
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")

        entradas: list[PointsEntry] = []
        for row in soup.select("div.sd-row[data-jornada]"):
            jornada_match = _JORNADA_NUM_RE.search(row.get("data-jornada", ""))
            if not jornada_match:
                continue
            try:
                puntos_por_modo = json.loads(row.get("data-puntos") or "{}")
            except json.JSONDecodeError:
                continue
            if not isinstance(puntos_por_modo, dict):
                continue
            valor = puntos_por_modo.get("laliga-fantasy")
            if valor is None:
                continue
            entradas.append(PointsEntry(jornada=int(jornada_match.group()), puntos=round(float(valor))))

        return sorted(entradas, key=lambda e: e.jornada)

    def get_all_players(self) -> list[Player]:
        jugadores = self._fetch_market()
        players: list[Player] = []
        for raw in jugadores.values():
            try:
                precio = int(raw["valor"]) if raw["valor"] else 0
            except (TypeError, ValueError):
                precio = 0
            players.append(
                Player(
                    id=raw["id"],
                    source=SOURCE_NAME,
                    nombre=raw["nombre"],
                    equipo=raw["equipo"],
                    posicion=POSITION_MAP_ES.get(raw["posicion_raw"], "UNK"),
                    precio=precio,
                )
            )
        return players

    def get_player_price_history(self, player_id: str) -> list[PricePoint]:
        if not self._market_cache:
            self._fetch_market()

        raw = self._market_cache.get(player_id)
        if not raw:
            return []

        hoy = dt.date.today()
        puntos: list[PricePoint] = []
        for dias in HISTORIAL_DIAS:
            valor = raw.get(f"valor{dias}")
            if not valor:
                continue
            try:
                precio = int(valor)
            except (TypeError, ValueError):
                continue
            fecha = hoy - dt.timedelta(days=dias)
            puntos.append(PricePoint(fecha=fecha.isoformat(), precio=precio))

        return sorted(puntos, key=lambda p: p.fecha)

    def get_player_points_history(self, player_id: str) -> list[PointsEntry]:
        # Desglose real jornada a jornada (ver docstring del módulo) — una
        # petición extra por jugador a /analytics/stats/detalle/.
        return self._fetch_jornadas(player_id)

    def get_next_opponent(self, player_id: str) -> str | None:
        if not self._puntos_cache:
            self._fetch_puntos()
        raw = self._puntos_cache.get(player_id) or {}
        return raw.get("proximo_rival") or None

    def get_rival_analysis(self, player_id: str) -> RivalAnalysis | None:
        # No hay forma pública de saber la dificultad del rival ni el
        # rendimiento histórico de un jugador contra un equipo concreto en
        # esta fuente (a diferencia de Biwenger, que sí lo da) — solo
        # exponemos el nombre del próximo rival, ya scrapeado de todas
        # formas para la media de puntos.
        texto = self.get_next_opponent(player_id)
        if not texto:
            return None
        # "Elche (Casa)" -> rival="Elche", casa=True.
        rival, _, resto = texto.rpartition(" (")
        casa = resto.strip(")") == "Casa"
        return RivalAnalysis(rival=rival or texto, casa=casa)

    def requires_auth_for_team(self) -> bool:
        return True

    def login(self, credentials: dict) -> AuthSession:
        # TODO fase 2b: pendiente de decisión consciente (ROPC contra un
        # tenant B2C de Azure AD, no una simple API key) — ver docstring.
        raise NotImplementedError("LaLigaFantasyAdapter.login: pendiente fase 2b (requiere ROPC, ver docstring)")

    def get_user_team(self, session: AuthSession) -> Team:
        # TODO fase 2b
        raise NotImplementedError("LaLigaFantasyAdapter.get_user_team: pendiente fase 2b")
