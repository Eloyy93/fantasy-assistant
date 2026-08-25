"""Adaptador para LaLiga Fantasy (Relevo, antes Marca).

# TODO fase 2: implementar contra la API real de LaLiga Fantasy.
# Requiere OAuth2 contra el tenant B2C de LaLiga (LALIGAFANTASY_CLIENT_ID /
# LALIGAFANTASY_CLIENT_SECRET en .env). De momento todos los métodos están
# sin implementar para que el resto del sistema compile y funcione con
# Biwenger mientras tanto.
"""
from __future__ import annotations

from fantasy_assistant.datasources.base import (
    AuthSession,
    FantasyDataSource,
    Player,
    PointsEntry,
    PricePoint,
    Team,
)

SOURCE_NAME = "laligafantasy"


class LaLigaFantasyAdapter(FantasyDataSource):
    def get_all_players(self) -> list[Player]:
        # TODO fase 2: llamar a la API pública de jugadores de LaLiga Fantasy.
        raise NotImplementedError("LaLigaFantasyAdapter.get_all_players: pendiente fase 2")

    def get_player_price_history(self, player_id: str) -> list[PricePoint]:
        # TODO fase 2
        raise NotImplementedError("LaLigaFantasyAdapter.get_player_price_history: pendiente fase 2")

    def get_player_points_history(self, player_id: str) -> list[PointsEntry]:
        # TODO fase 2
        raise NotImplementedError("LaLigaFantasyAdapter.get_player_points_history: pendiente fase 2")

    def requires_auth_for_team(self) -> bool:
        return True

    def login(self, credentials: dict) -> AuthSession:
        # TODO fase 2: flujo OAuth2 B2C (authorization code / device code).
        raise NotImplementedError("LaLigaFantasyAdapter.login: pendiente fase 2 (OAuth2 B2C)")

    def get_user_team(self, session: AuthSession) -> Team:
        # TODO fase 2
        raise NotImplementedError("LaLigaFantasyAdapter.get_user_team: pendiente fase 2")
