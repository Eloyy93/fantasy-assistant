"""Módulo 1 — Predictor de precio (v1, reglas simples, no ML).

Regla: compara la media de puntos de las últimas N jornadas con la media
histórica del jugador. Si el ratio supera `up_threshold` -> "sube"; si cae
por debajo de `down_threshold` -> "baja"; en otro caso -> "estable".
"""
from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select

from fantasy_assistant.config import config
from fantasy_assistant.db.database import get_session
from fantasy_assistant.db.models import PointsHistory

RECENT_WINDOW = 3


@dataclass
class PricePrediction:
    player_id: str
    prediccion: str  # "sube" | "baja" | "estable"
    confianza: float  # 0..1


def _mean(values: list[int]) -> float:
    return sum(values) / len(values) if values else 0.0


def predict_for_points(historial_puntos: list[int]) -> tuple[str, float]:
    """Aplica la regla v1 sobre una lista de puntos ordenada de jornada más
    antigua a más reciente. Función pura, testeable sin BD."""
    if len(historial_puntos) < 2:
        return "estable", 0.0

    media_historica = _mean(historial_puntos)
    recientes = historial_puntos[-RECENT_WINDOW:]
    media_reciente = _mean(recientes)

    if media_historica == 0:
        return "estable", 0.0

    ratio = media_reciente / media_historica

    if ratio >= config.price_predictor_up_threshold:
        prediccion = "sube"
    elif ratio <= config.price_predictor_down_threshold:
        prediccion = "baja"
    else:
        prediccion = "estable"

    # Confianza: qué tan lejos está el ratio de 1.0 (neutro), acotado a [0,1],
    # ponderado por cuántos datos tenemos (más jornadas = más confianza).
    distancia = min(abs(ratio - 1.0), 1.0)
    cobertura = min(len(historial_puntos) / 5, 1.0)
    confianza = round(distancia * cobertura, 2) if prediccion != "estable" else round((1 - distancia) * cobertura, 2)

    return prediccion, confianza


def predict_player(player_id: str) -> PricePrediction:
    with get_session() as session:
        rows = session.execute(
            select(PointsHistory)
            .where(PointsHistory.player_id == player_id)
            .order_by(PointsHistory.jornada)
        ).scalars().all()
        historial = [r.puntos for r in rows]

    prediccion, confianza = predict_for_points(historial)
    return PricePrediction(player_id=player_id, prediccion=prediccion, confianza=confianza)
