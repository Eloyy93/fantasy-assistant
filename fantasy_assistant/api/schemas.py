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
