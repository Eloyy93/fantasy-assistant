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
- get_player_points_history(): no hay desglose público jornada a jornada,
  pero `/analytics/laliga-fantasy/puntos` sí trae, por jugador y en el mismo
  HTML servido por el servidor, la media de puntos de sus últimos 3 y 5
  partidos (`data-media3` / `data-media5`) y el acumulado de temporada
  (`data-puntostemporada`). Para que el optimizador (que calcula "puntos
  esperados" como la media de las últimas 3 jornadas conocidas en
  PointsHistory) funcione igual de bien con esta fuente que con Biwenger,
  sintetizamos 3 entradas de PointsHistory con jornada=-1,-2,-3 y
  puntos=media3 redondeada — su media da exactamente media3, sin inventar
  un desglose por jornada que no existe públicamente.
- login() / get_user_team(): sin implementar a propósito — requieren ROPC
  contra un tenant B2C de Azure AD, no una API key, y sigue sin resolverse
  la decisión consciente de si merece la pena perseguir eso (ver TODO
  histórico más abajo).
"""
from __future__ import annotations

import datetime as dt
import logging
import re

import requests
from bs4 import BeautifulSoup
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from fantasy_assistant.datasources.base import (
    AuthSession,
    FantasyDataSource,
    Player,
    PointsEntry,
    PricePoint,
    Team,
)

logger = logging.getLogger(__name__)

MARKET_URL = "https://www.futbolfantasy.com/analytics/laliga-fantasy/mercado"
PUNTOS_URL = "https://www.futbolfantasy.com/analytics/laliga-fantasy/puntos"

_ONCLICK_ID_RE = re.compile(r"openPlayerPointsStats\((\d+)")

POSITION_MAP_ES = {
    "Portero": "POR",
    "Defensa": "DEF",
    "Mediocampista": "MED",
    "Delantero": "DEL",
}

# data-valorN = precio hace N días (aproximado a partir de hoy).
HISTORIAL_DIAS = (1, 2, 3, 7, 14, 30)

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
        soup = BeautifulSoup(resp.text, "html.parser")

        jugadores: dict[str, dict] = {}
        for row in soup.select("tr.elemento_jugador[data-nombre]"):
            match = _ONCLICK_ID_RE.search(row.get("onclick", ""))
            if not match:
                continue
            player_id = match.group(1)
            jugadores[player_id] = {
                "media3": row.get("data-media3"),
                "media5": row.get("data-media5"),
                "puntostemporada": row.get("data-puntostemporada"),
            }

        self._puntos_cache = jugadores
        return jugadores

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
        # No hay desglose público por jornada, pero sí la media de puntos
        # de los últimos 3 partidos (ver docstring del módulo). Sintetizamos
        # 3 entradas con esa media para que el optimizador (que promedia las
        # últimas 3 jornadas en PointsHistory) reciba la misma señal que le
        # daría un desglose real.
        if not self._puntos_cache:
            self._fetch_puntos()

        raw = self._puntos_cache.get(player_id)
        if not raw or not raw.get("media3"):
            return []

        try:
            media3 = float(raw["media3"])
        except (TypeError, ValueError):
            return []

        puntos = round(media3)
        return [PointsEntry(jornada=j, puntos=puntos) for j in (-1, -2, -3)]

    def requires_auth_for_team(self) -> bool:
        return True

    def login(self, credentials: dict) -> AuthSession:
        # TODO fase 2b: pendiente de decisión consciente (ROPC contra un
        # tenant B2C de Azure AD, no una simple API key) — ver docstring.
        raise NotImplementedError("LaLigaFantasyAdapter.login: pendiente fase 2b (requiere ROPC, ver docstring)")

    def get_user_team(self, session: AuthSession) -> Team:
        # TODO fase 2b
        raise NotImplementedError("LaLigaFantasyAdapter.get_user_team: pendiente fase 2b")
