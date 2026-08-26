"""Carga la configuración de la app desde variables de entorno (.env)."""
from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

# override=True: el .env de este proyecto manda incluso si ya existe una
# variable de entorno del mismo nombre en el sistema (ej. otro proyecto en
# la misma máquina) — si no, se cuela silenciosamente.
load_dotenv(override=True)


def _float_env(name: str, default: float) -> float:
    value = os.getenv(name)
    return float(value) if value else default


@dataclass(frozen=True)
class Config:
    fantasy_source: str = field(default_factory=lambda: os.getenv("FANTASY_SOURCE", "biwenger").lower())
    database_url: str = field(default_factory=lambda: os.getenv("DATABASE_URL", "sqlite:///fantasy_assistant.db"))

    biwenger_email: str = field(default_factory=lambda: os.getenv("BIWENGER_EMAIL", ""))
    biwenger_password: str = field(default_factory=lambda: os.getenv("BIWENGER_PASSWORD", ""))

    laligafantasy_client_id: str = field(default_factory=lambda: os.getenv("LALIGAFANTASY_CLIENT_ID", ""))
    laligafantasy_client_secret: str = field(default_factory=lambda: os.getenv("LALIGAFANTASY_CLIENT_SECRET", ""))

    # Umbrales del predictor de precio: ratio (media últimas jornadas / media histórica)
    price_predictor_up_threshold: float = field(
        default_factory=lambda: _float_env("PRICE_PREDICTOR_UP_THRESHOLD", 1.15)
    )
    price_predictor_down_threshold: float = field(
        default_factory=lambda: _float_env("PRICE_PREDICTOR_DOWN_THRESHOLD", 0.85)
    )

    # % de cambio de precio (entre dos sincronizaciones) a partir del cual se dispara una alerta push
    price_change_alert_threshold: float = field(
        default_factory=lambda: _float_env("PRICE_CHANGE_ALERT_THRESHOLD", 0.03)
    )

    # Ruta a la clave de cuenta de servicio de Firebase (JSON), para enviar notificaciones push
    firebase_credentials_path: str = field(default_factory=lambda: os.getenv("FIREBASE_CREDENTIALS_PATH", ""))
    # Alternativa: el JSON completo de la cuenta de servicio como string (más cómodo en Railway)
    firebase_credentials_json: str = field(default_factory=lambda: os.getenv("FIREBASE_CREDENTIALS_JSON", ""))

    def __post_init__(self) -> None:
        if self.fantasy_source not in ("biwenger", "laligafantasy"):
            raise ValueError(
                f"FANTASY_SOURCE inválido: {self.fantasy_source!r}. Usa 'biwenger' o 'laligafantasy'."
            )


config = Config()
