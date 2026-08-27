"""Contrato común que deben cumplir todos los adaptadores de fuente de datos.

El resto de la app (BD, módulos de análisis, API) solo debe hablar con
`FantasyDataSource`, nunca con un adaptador concreto.
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


@dataclass
class RivalAnalysis:
    rival: str
    casa: bool
    # 0 (rival flojo) .. 100 (rival top), escala de Biwenger. None si la
    # fuente no la calcula (ej. LaLiga Fantasy).
    dificultad: int | None = None
    partidos_previos: int | None = None
    puntos_previos: int | None = None
    media_previos: float | None = None


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

    def get_next_opponent(self, player_id: str) -> str | None:
        """Próximo rival del equipo del jugador, ej. "Barcelona (Fuera)".
        None si no se pudo determinar. No es abstracto (default None) para
        no obligar a implementarlo en fuentes futuras que no lo tengan;
        usado por /compare, no crítico para el resto de la app."""
        return None

    def get_rival_analysis(self, player_id: str) -> RivalAnalysis | None:
        """Próximo rival + qué tan difícil es + cómo le ha ido a este
        jugador contra ese rival concreto en el pasado, cuando la fuente lo
        ofrezca (Biwenger sí, con datos ricos; LaLiga Fantasy solo el
        nombre del rival, sin dificultad ni histórico). None si no hay
        próximo partido conocido. Usado por /compare y por el predictor de
        precio (módulo 1) para ajustar la confianza según el calendario."""
        return None
