"""Adaptador para LaLiga Fantasy (Relevo, antes Marca).

API no oficial, sin documentación pública de LALIGA. Endpoints y forma de
los datos confirmados a partir de proyectos open-source que ya la habían
reverse-engineered (varios repos públicos en GitHub referencian el mismo
host `api-fantasy.llt-services.com`, verificados contra la API real en
fechas recientes) — no directamente por mí en este entorno, porque el
backend de LALIGA está devolviendo 502 (Azure Application Gateway) en el
momento de escribir esto. Trátese como implementado-pero-no-verificado en
vivo hasta la primera sincronización real.

Cobertura:
- get_all_players(): sí, endpoint público `/api/v5/players`, sin auth.
- get_player_price_history(): sí, endpoint público `/api/v3/player/{id}/market-value`,
  pero el nombre exacto de los campos del JSON no está confirmado (no pude
  verlo en vivo) — el parseo prueba varios nombres razonables y, si no
  encaja ninguno, devuelve lista vacía en vez de reventar.
- get_player_points_history(): no se encontró ningún endpoint público con
  puntos por jornada; solo el acumulado de temporada, que ya viene en
  get_all_players(). Devuelve lista vacía.
- login() / get_user_team(): requieren ROPC (Resource Owner Password
  Credentials) contra un tenant B2C de Azure AD — flujo de autenticación
  real de usuario, no una API key. No implementado: además de la
  complejidad, un proyecto que reverse-engineered esto en detalle (agosto
  2026) documentó que había bloqueado explícitamente esa parte "hasta
  autorización escrita de LALIGA". Aplico la misma cautela aquí — se deja
  como TODO fase 2b, a decidir conscientemente, no un simple "falta tiempo".

# TODO fase 2b: login() vía ROPC si se decide seguir adelante con ello
# (LALIGAFANTASY_CLIENT_ID / LALIGAFANTASY_CLIENT_SECRET en .env), y
# get_user_team() sobre /api/v4/leagues + /api/v4/leagues/{id}/teams/{id}.
# TODO: resolver nombre de equipo real a partir de teamId — no se encontró
# endpoint público de catálogo de equipos; de momento `equipo` es el
# teamId tal cual.
"""
from __future__ import annotations

import logging

import requests
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

BASE_URL = "https://api-fantasy.llt-services.com"

# Mismo convenio que Biwenger (1=portero..4=delantero), consistente con los
# ejemplos de payload documentados por varios de estos proyectos.
POSITION_MAP = {1: "POR", 2: "DEF", 3: "MED", 4: "DEL"}

SOURCE_NAME = "laligafantasy"


class LaLigaFantasyAdapter(FantasyDataSource):
    def __init__(self, session: requests.Session | None = None) -> None:
        self._http = session or requests.Session()
        self._http.headers.update({"User-Agent": "Mozilla/5.0 (fantasy-assistant)"})

    @retry(
        reraise=True,
        stop=stop_after_attempt(4),
        wait=wait_exponential(multiplier=1, min=1, max=20),
        retry=retry_if_exception_type((requests.ConnectionError, requests.Timeout, requests.HTTPError)),
    )
    def _get(self, path: str, **kwargs) -> object:
        resp = self._http.get(f"{BASE_URL}{path}", timeout=15, **kwargs)
        if resp.status_code in (429, 502, 503):
            raise requests.HTTPError(f"LaLiga Fantasy no disponible temporalmente: {resp.status_code}")
        resp.raise_for_status()
        return resp.json()

    def get_all_players(self) -> list[Player]:
        payload = self._get("/api/v5/players", params={"x-lang": "es"})
        players: list[Player] = []
        for raw in payload:
            try:
                position_id = int(raw.get("positionId", 0))
            except (TypeError, ValueError):
                position_id = 0
            players.append(
                Player(
                    id=str(raw.get("id")),
                    source=SOURCE_NAME,
                    nombre=raw.get("nickname", ""),
                    # TODO: sin catálogo público de equipos confirmado, se
                    # deja el teamId tal cual en vez de inventar un nombre.
                    equipo=str(raw.get("teamId", "")),
                    posicion=POSITION_MAP.get(position_id, "UNK"),
                    precio=int(raw.get("marketValue") or 0),
                )
            )
        return players

    def get_player_price_history(self, player_id: str) -> list[PricePoint]:
        payload = self._get(f"/api/v3/player/{player_id}/market-value", params={"x-lang": "es"})
        if not isinstance(payload, list):
            logger.warning("market-value de %s no es una lista, forma inesperada: %s", player_id, type(payload))
            return []

        puntos: list[PricePoint] = []
        for entry in payload:
            if not isinstance(entry, dict):
                continue
            fecha = entry.get("date") or entry.get("fecha") or entry.get("day")
            precio = entry.get("marketValue") or entry.get("value") or entry.get("valor")
            if fecha is None or precio is None:
                continue
            try:
                puntos.append(PricePoint(fecha=str(fecha), precio=int(precio)))
            except (TypeError, ValueError):
                continue

        if not puntos and payload:
            logger.warning(
                "market-value de %s: no se reconoció ningún campo de fecha/precio esperado en %s",
                player_id,
                list(payload[0].keys()) if isinstance(payload[0], dict) else payload[0],
            )
        return puntos

    def get_player_points_history(self, player_id: str) -> list[PointsEntry]:
        # No se encontró endpoint público con el desglose de puntos por
        # jornada (solo el acumulado de temporada, que ya viene en el
        # listado de jugadores). sync_data.py sigue funcionando sin esto,
        # simplemente sin histórico jornada a jornada para esta fuente.
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
