"""Módulo 3 — Alertas.

v1: alerta por cambio de precio significativo entre dos sincronizaciones
consecutivas. Se dispara desde jobs/sync_data.py, que conoce el precio
anterior y el nuevo de cada jugador. El envío real (push FCM) vive en
fantasy_assistant/notifications/fcm.py — este módulo solo decide *si* hay
alerta, no cómo se entrega.

# TODO fase 3b: alertas también por cambio de categoría del predictor
# (price_predictor.predict_player), y suscripciones por jugador (tabla
# `subscriptions`: device_id/chat_id, player_id) en vez de notificar a todos
# los dispositivos registrados por igual.
"""
from __future__ import annotations

from dataclasses import dataclass

from fantasy_assistant.config import config


@dataclass
class Alert:
    player_id: str
    mensaje: str


def check_price_change(
    player_id: str,
    nombre: str,
    precio_anterior: int | None,
    precio_nuevo: int,
) -> Alert | None:
    """Compara el precio anterior conocido de un jugador con el nuevo tras
    una sincronización. Devuelve una alerta si el cambio supera el umbral."""
    if precio_anterior is None or precio_anterior == 0:
        return None

    ratio = precio_nuevo / precio_anterior
    cambio = ratio - 1.0
    if abs(cambio) < config.price_change_alert_threshold:
        return None

    direccion = "subido" if cambio > 0 else "bajado"
    porcentaje = abs(cambio) * 100
    mensaje = (
        f"{nombre} ha {direccion} un {porcentaje:.1f}% "
        f"({precio_anterior / 1_000_000:.2f} M€ → {precio_nuevo / 1_000_000:.2f} M€)"
    )
    return Alert(player_id=player_id, mensaje=mensaje)
