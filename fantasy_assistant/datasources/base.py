"""Contrato común que deben cumplir todos los adaptadores de fuente de datos.

El resto de la app (BD, módulos de análisis, bot de Telegram) solo debe hablar
con `FantasyDataSource`, nunca con un adaptador concreto.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass
class Player:
    id: str
    source: str
    nombre: str
    equipo: str
    posicion: str  # POR | DEF | MED | DEL
    precio: int


@dataclass
class PricePoint:
    fecha: str  # ISO date
    precio: int


@dataclass
class PointsEntry:
    jornada: int
    puntos: int


@dataclass
class AuthSession:
    token: str
    extra: dict = field(default_factory=dict)


@dataclass
class TeamPlayer:
    player_id: str
    en_alineacion: bool = False


@dataclass
class Team:
    user_id: str
    presupuesto: int
    jugadores: list[TeamPlayer]


class FantasyDataSource(ABC):
    """Interfaz que deben implementar BiwengerAdapter y LaLigaFantasyAdapter."""

    @abstractmethod
    def get_all_players(self) -> list[Player]: ...

    @abstractmethod
    def get_player_price_history(self, player_id: str) -> list[PricePoint]: ...

    @abstractmethod
    def get_player_points_history(self, player_id: str) -> list[PointsEntry]: ...

    @abstractmethod
    def requires_auth_for_team(self) -> bool: ...

    @abstractmethod
    def login(self, credentials: dict) -> AuthSession: ...

    @abstractmethod
    def get_user_team(self, session: AuthSession) -> Team: ...
