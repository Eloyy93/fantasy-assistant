from __future__ import annotations

from pydantic import BaseModel


class PlayerOut(BaseModel):
    id: str
    source: str
    nombre: str
    equipo: str
    posicion: str
    precio: int

    model_config = {"from_attributes": True}


class PrediccionOut(BaseModel):
    player_id: str
    prediccion: str
    confianza: float


class DeviceRegisterIn(BaseModel):
    fcm_token: str
    user_id: str | None = None


class SubscriptionIn(BaseModel):
    fcm_token: str
    player_id: str


class LineupPlayerOut(BaseModel):
    player_id: str
    nombre: str
    equipo: str
    posicion: str
    precio: int
    puntos_esperados: float


class OptimizedLineupOut(BaseModel):
    formacion: str
    jugadores: list[LineupPlayerOut]
    puntos_esperados: float
    presupuesto_usado: int


class PricePointOut(BaseModel):
    fecha: str
    precio: int


class PointsEntryOut(BaseModel):
    jornada: int
    puntos: int


class PlayerHistorialOut(BaseModel):
    precios: list[PricePointOut]
    puntos: list[PointsEntryOut]


class TeamMemberIn(BaseModel):
    device_id: str
    player_id: str


class TeamPlayerOut(BaseModel):
    id: str
    source: str
    nombre: str
    equipo: str
    posicion: str
    precio: int
    # None si aún no hay suficiente histórico para calcular la variación.
    variacion_precio: int | None = None
    puntos_ultima_jornada: int | None = None
    puntos_temporada: int
