"""Carga la configuración de la app desde variables de entorno (.env)."""
from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()


def _float_env(name: str, default: float) -> float:
    value = os.getenv(name)
    return float(value) if value else default


@dataclass(frozen=True)
class Config:
    fantasy_source: str = field(default_factory=lambda: os.getenv("FANTASY_SOURCE", "biwenger").lower())
    database_url: str = field(default_factory=lambda: os.getenv("DATABASE_URL", "sqlite:///fantasy_assistant.db"))

    telegram_bot_token: str = field(default_factory=lambda: os.getenv("TELEGRAM_BOT_TOKEN", ""))

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

    def __post_init__(self) -> None:
        if self.fantasy_source not in ("biwenger", "laligafantasy"):
            raise ValueError(
                f"FANTASY_SOURCE inválido: {self.fantasy_source!r}. Usa 'biwenger' o 'laligafantasy'."
            )


config = Config()
