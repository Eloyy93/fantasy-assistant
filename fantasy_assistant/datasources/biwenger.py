"""Adaptador real para Biwenger (API no oficial).

Toda llamada HTTP a Biwenger vive aquí para poder parchear rápido si cambian
algo, sin que el resto de la app se entere.

get_player_price_history() usa `/players/la-liga/{id}?fields=id,prices` —
un endpoint público que, pedido con esos `fields` explícitos, devuelve 365
días de histórico de precio por jugador (no lo devuelve si no se piden). Es
una petición extra por jugador (no viene en get_all_players), con un
pequeño margen entre peticiones para no saturar la API.
"""
from __future__ import annotations

import datetime as dt
import logging
import time

import requests
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from fantasy_assistant.config import config
from fantasy_assistant.datasources.base import (
    AuthSession,
    FantasyDataSource,
    Player,
    PointsEntry,
    PricePoint,
    Team,
    TeamPlayer,
)

logger = logging.getLogger(__name__)

BASE_URL = "https://cf.biwenger.com/api/v2"
COMPETITION_DATA_URL = f"{BASE_URL}/competitions/la-liga/data"
PLAYER_URL = f"{BASE_URL}/players/la-liga/{{player_id}}"
LOGIN_URL = f"{BASE_URL}/auth/login"

# get_player_price_history hace una petición extra por jugador (no viene en
# get_all_players) — este margen evita saturar la API con ~567 peticiones
# seguidas. 0.15s pareció seguro en ráfagas cortas (70 peticiones) pero
# Biwenger rate-limitó igualmente a mitad de una sincronización completa
# (567 jugadores) — subido a 1s tras esa prueba real.
PRICE_HISTORY_THROTTLE_SECONDS = 1.0

# Códigos de posición usados por Biwenger, traducidos a abreviaturas en castellano.
POSITION_MAP = {1: "POR", 2: "DEF", 3: "MED", 4: "DEL"}

SOURCE_NAME = "biwenger"


class BiwengerAdapter(FantasyDataSource):
    def __init__(self, session: requests.Session | None = None) -> None:
        self._http = session or requests.Session()
        self._http.headers.update({"User-Agent": "Mozilla/5.0 (fantasy-assistant)"})
        # Se activa en cuanto Biwenger devuelve un 429 en get_player_price_history,
        # para dejar de pedir histórico al resto de jugadores de esta
        # sincronización (ver comentario en ese método).
        self._price_history_blocked = False

    @retry(
        reraise=True,
        stop=stop_after_attempt(4),
        wait=wait_exponential(multiplier=1, min=1, max=20),
        retry=retry_if_exception_type((requests.ConnectionError, requests.Timeout, requests.HTTPError)),
    )
    def _get(self, url: str, **kwargs) -> dict:
        resp = self._http.get(url, timeout=15, **kwargs)
        if resp.status_code == 429:
            raise requests.HTTPError(f"Rate limited por Biwenger: {resp.status_code}")
        resp.raise_for_status()
        return resp.json()

    def get_all_players(self) -> list[Player]:
        payload = self._get(COMPETITION_DATA_URL, params={"lang": "es", "score": 2})
        data = payload.get("data", {})
        teams = data.get("teams", {})
        players_raw = data.get("players", {})

        players: list[Player] = []
        for player_id, raw in players_raw.items():
            team_id = raw.get("teamID")
            team = teams.get(str(team_id)) or teams.get(team_id) or {}
            players.append(
                Player(
                    id=str(player_id),
                    source=SOURCE_NAME,
                    nombre=raw.get("name", ""),
                    equipo=team.get("name", ""),
                    posicion=POSITION_MAP.get(raw.get("position"), "UNK"),
                    precio=raw.get("price") or 0,
                )
            )
        return players

    @retry(
        reraise=True,
        stop=stop_after_attempt(2),
        wait=wait_exponential(multiplier=1, min=1, max=5),
        retry=retry_if_exception_type((requests.ConnectionError, requests.Timeout)),
    )
    def get_player_price_history(self, player_id: str) -> list[PricePoint]:
        # Descubierto por prueba y error: el endpoint público de ficha de
        # jugador SÍ da histórico de precio (365 días, uno por día) si se
        # piden explícitamente los campos "prices" — no viene si no se pide.
        # Formato de cada punto: [fecha_YYMMDD, precio].
        #
        # ¡Ojo! No reintentar 429 con backoff exponencial como el resto de
        # peticiones: verificado en producción que Biwenger rate-limita esta
        # ruta con bastante agresividad (un margen de 0.15s entre peticiones
        # ya lo disparó a mitad de sync), y reintentar cada jugador varias
        # veces con esperas crecientes convirtió una sincronización de
        # minutos en una de más de una hora, con 450/567 jugadores fallando
        # igualmente. Si llega un 429, nos rendimos para este jugador ya
        # (sin reintentar) — se recupera solo en la siguiente sincronización.
        if self._price_history_blocked:
            return []

        time.sleep(PRICE_HISTORY_THROTTLE_SECONDS)
        resp = self._http.get(
            PLAYER_URL.format(player_id=player_id),
            params={"lang": "es", "fields": "id,prices"},
            timeout=15,
        )
        if resp.status_code == 404:
            return []
        if resp.status_code == 429:
            # Una vez rate-limitados, es casi seguro que el resto de
            # peticiones de esta sincronización también lo estarán —dejar de
            # intentarlo en vez de encadenar cientos de 429 más.
            logger.warning("Biwenger rate-limitó el histórico de precio (429) — se omite el resto de esta sincronización")
            self._price_history_blocked = True
            return []
        resp.raise_for_status()
        prices = resp.json().get("data", {}).get("prices") or []

        puntos: list[PricePoint] = []
        for fecha_raw, precio in prices:
            try:
                fecha = dt.datetime.strptime(str(fecha_raw), "%y%m%d").date()
            except ValueError:
                continue
            puntos.append(PricePoint(fecha=fecha.isoformat(), precio=precio))
        return puntos

    def get_player_points_history(self, player_id: str) -> list[PointsEntry]:
        # Igual que con el precio: el endpoint público de datos de competición
        # solo trae el campo `fitness` (puntos de los últimos partidos) para
        # todos los jugadores a la vez. Lo exponemos aquí releyendo esa misma
        # llamada; sync_data.py es quien lo persiste jornada a jornada en BD.
        payload = self._get(COMPETITION_DATA_URL, params={"lang": "es", "score": 2})
        players_raw = payload.get("data", {}).get("players", {})
        raw = players_raw.get(player_id) or players_raw.get(int(player_id))
        if not raw:
            return []
        fitness = raw.get("fitness") or []
        entries = []
        # fitness viene ordenado de más antiguo a más reciente. Puede traer
        # `None` (jornada no jugada) o strings de estado como "injured" en
        # vez de puntos numéricos; ambos se descartan.
        for idx, puntos in enumerate(fitness, start=1):
            if not isinstance(puntos, int):
                continue
            entries.append(PointsEntry(jornada=idx, puntos=puntos))
        return entries

    def get_next_opponent(self, player_id: str) -> str | None:
        # La misma llamada de datos de competición trae, por equipo, su
        # próximo partido (`nextGames`) — sin petición extra por jugador.
        payload = self._get(COMPETITION_DATA_URL, params={"lang": "es", "score": 2})
        data = payload.get("data", {})
        players_raw = data.get("players", {})
        teams = data.get("teams", {})

        raw = players_raw.get(player_id) or players_raw.get(int(player_id))
        if not raw:
            return None
        team_id = raw.get("teamID")
        team = teams.get(str(team_id)) or teams.get(team_id) or {}
        next_games = team.get("nextGames") or []
        if not next_games:
            return None

        partido = next_games[0]
        home_id = (partido.get("home") or {}).get("id")
        away_id = (partido.get("away") or {}).get("id")
        es_local = home_id == team_id
        rival_id = away_id if es_local else home_id
        rival = teams.get(str(rival_id)) or teams.get(rival_id) or {}
        rival_nombre = rival.get("name")
        if not rival_nombre:
            return None
        return f"{rival_nombre} ({'Casa' if es_local else 'Fuera'})"

    def requires_auth_for_team(self) -> bool:
        return True

    def login(self, credentials: dict) -> AuthSession:
        email = credentials.get("email") or config.biwenger_email
        password = credentials.get("password") or config.biwenger_password
        if not email or not password:
            raise ValueError("Se requiere email y password para login en Biwenger")

        resp = self._http.post(
            LOGIN_URL,
            json={"email": email, "password": password},
            timeout=15,
        )
        resp.raise_for_status()
        payload = resp.json()
        token = payload.get("token") or payload.get("data", {}).get("token")
        if not token:
            raise RuntimeError("Login en Biwenger no devolvió token")
        return AuthSession(token=token, extra=payload.get("data", {}))

    def get_user_team(self, session: AuthSession) -> Team:
        headers = {"Authorization": f"Bearer {session.token}"}
        payload = self._get(f"{BASE_URL}/user", headers=headers, params={"lang": "es"})
        data = payload.get("data", {})
        account = data.get("account", {})
        players = [
            TeamPlayer(player_id=str(p.get("id")), en_alineacion=bool(p.get("owner")))
            for p in data.get("players", [])
        ]
        return Team(
            user_id=str(account.get("id", "")),
            presupuesto=account.get("balance", 0),
            jugadores=players,
        )
