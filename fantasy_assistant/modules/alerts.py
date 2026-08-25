"""Módulo 3 — Alertas.

# TODO fase 3: implementar.
# jobs/sync_data.py debe llamar aquí tras cada sincronización para:
#   1. Comparar el snapshot nuevo con el anterior (precio y categoría de
#      price_predictor.predict_player) por jugador.
#   2. Si hay cambio de precio significativo o cambio de categoría de
#      predicción -> generar una alerta.
#   3. Las alertas se entregan vía bot/telegram_bot.py a los chat_id
#      suscritos a ese jugador (comando /alertas on|off <jugador>).
# Falta decidir dónde persistir las suscripciones (nueva tabla `subscriptions`
# en db/models.py: chat_id, player_id).
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Alert:
    player_id: str
    mensaje: str


def check_for_alerts(player_id: str) -> list[Alert]:
    # TODO fase 3
    raise NotImplementedError("alerts.check_for_alerts: pendiente fase 3")
