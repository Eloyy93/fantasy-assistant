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
- get_player_points_history(): no se encontró ninguna fuente pública con
  puntos por jornada de LaLiga Fantasy. Devuelve lista vacía.
- login() / get_user_team(): sin implementar a propósito — requieren ROPC
  contra un tenant B2C de Azure AD, no una API key, y sigue sin resolverse
  la decisión consciente de si merece la pena perseguir eso (ver TODO
  histórico más abajo).
"""
from __future__ import annotations

import datetime as dt
import logging

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
        # No se encontró ninguna fuente pública con puntos por jornada de
        # LaLiga Fantasy (solo el acumulado de temporada, no desglosado).
        return []

    def requires_auth_for_team(self) -> bool:
        return True

    def login(self, credentials: dict) -> AuthSession:
        # TODO fase 2b: pendiente de decisión consciente (ROPC contra un
        # tenant B2C de Azure AD, no una simple API key) — ver docstring.
        raise NotImplementedError("LaLigaFantasyAdapter.login: pendiente fase 2b (requiere ROPC, ver docstring)")

    def get_user_team(self, session: AuthSession) -> Team:
        # TODO fase 2b
        raise NotImplementedError("LaLigaFantasyAdapter.get_user_team: pendiente fase 2b")
