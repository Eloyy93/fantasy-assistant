from __future__ import annotations

from pydantic import BaseModel


class PlayerOut(BaseModel):
    id: str
    source: str
    nombre: str
    equipo: str
    posicion: str
    precio: int
    foto_url: str = ""

    model_config = {"from_attributes": True}


class PrediccionOut(BaseModel):
    player_id: str
    prediccion: str
    confianza: float
    rival: RivalAnalysisOut | None = None


class RivalAnalysisOut(BaseModel):
    rival: str
    casa: bool
    # None si la fuente no la calcula (hoy: solo Biwenger da dificultad e
    # histórico contra el rival concreto; LaLiga Fantasy solo el nombre).
    dificultad: int | None = None
    partidos_previos: int | None = None
    puntos_previos: int | None = None
    media_previos: float | None = None


class DeviceRegisterIn(BaseModel):
    fcm_token: str
    user_id: str | None = None


class ChollosPrefIn(BaseModel):
    fcm_token: str
    activar: bool


class BargainOut(BaseModel):
    id: str
    nombre: str
    equipo: str
    posicion: str
    precio: int
    puntos_esperados: float
    ratio: float
    zscore: float
    foto_url: str = ""


class CaptainOut(BaseModel):
    id: str
    nombre: str
    equipo: str
    posicion: str
    foto_url: str = ""
    puntos_esperados: float
    score: float
    proximo_rival: str | None = None
    dificultad_rival: int | None = None


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
    foto_url: str = ""


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
    # Hueco exacto de la formación (ej. "DEF2"). None = jugador en la
    # plantilla sin colocar en el campo (banquillo).
    slot: str | None = None


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
    slot: str | None = None
    foto_url: str = ""


class FormationIn(BaseModel):
    device_id: str
    source: str
    formacion: str


class FormationOut(BaseModel):
    formacion: str


class ComparePlayerOut(BaseModel):
    id: str
    source: str
    nombre: str
    equipo: str
    posicion: str
    precio: int
    foto_url: str = ""
    variacion_precio: int | None = None
    puntos_recientes: list[PointsEntryOut]
    puntos_temporada: int
    proximo_rival: str | None = None
    analisis_rival: RivalAnalysisOut | None = None


class CompareOut(BaseModel):
    a: ComparePlayerOut
    b: ComparePlayerOut
