"""Módulo 1 — Predictor de precio (v1, reglas simples, no ML).

Regla base: compara la media de puntos de las últimas N jornadas con la
media histórica del jugador. Si el ratio supera `up_threshold` -> "sube"; si
cae por debajo de `down_threshold` -> "baja"; en otro caso -> "estable".

Ajuste de calendario: si la fuente sabe qué tan difícil es el próximo rival
(`FantasyDataSource.get_rival_analysis()`, hoy solo Biwenger da esa
dificultad), se usa para subir o bajar la confianza — nunca para cambiar la
dirección de la predicción en sí, que sigue basándose solo en los puntos
reales. Un rival flojo que refuerza una tendencia de subida da más
seguridad; un rival duro que la contradice, menos.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

from sqlalchemy import select

from fantasy_assistant.config import config
from fantasy_assistant.datasources import get_data_source
from fantasy_assistant.datasources.base import RivalAnalysis
from fantasy_assistant.db.database import get_session
from fantasy_assistant.db.models import PlayerRecord, PointsHistory

logger = logging.getLogger(__name__)

RECENT_WINDOW = 3
# Cuánto puede mover la confianza el ajuste por calendario, como máximo.
RIVAL_CONFIDENCE_ADJUST = 0.1


@dataclass
class PricePrediction:
    player_id: str
    prediccion: str  # "sube" | "baja" | "estable"
    confianza: float  # 0..1
    rival: RivalAnalysis | None = None


def _mean(values: list[int]) -> float:
    return sum(values) / len(values) if values else 0.0


def predict_for_points(historial_puntos: list[int], dificultad_rival: int | None = None) -> tuple[str, float]:
    """Aplica la regla v1 sobre una lista de puntos ordenada de jornada más
    antigua a más reciente. Función pura, testeable sin BD.

    `dificultad_rival` (0=flojo..100=top, escala de Biwenger) es opcional:
    si se da, ajusta la confianza según si el próximo partido refuerza o
    contradice la tendencia detectada — nunca cambia "sube"/"baja"/"estable"."""
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
    confianza = distancia * cobertura if prediccion != "estable" else (1 - distancia) * cobertura

    if dificultad_rival is not None and prediccion != "estable":
        rival_favorece_subida = dificultad_rival < 50
        coherente = (prediccion == "sube") == rival_favorece_subida
        confianza += RIVAL_CONFIDENCE_ADJUST if coherente else -RIVAL_CONFIDENCE_ADJUST

    return prediccion, round(min(max(confianza, 0.0), 1.0), 2)


def predict_player(player_id: str) -> PricePrediction:
    with get_session() as session:
        rows = session.execute(
            select(PointsHistory)
            .where(PointsHistory.player_id == player_id)
            .order_by(PointsHistory.jornada)
        ).scalars().all()
        historial = [r.puntos for r in rows]
        player = session.get(PlayerRecord, player_id)

    analisis: RivalAnalysis | None = None
    if player:
        try:
            analisis = get_data_source(player.source).get_rival_analysis(player.external_id)
        except Exception:
            # El ajuste por calendario es un extra, no algo crítico — si la
            # fuente falla (red, rate-limit...) seguimos con la predicción
            # base en vez de romper /players/{id}/prediccion entero.
            logger.warning("No se pudo obtener el análisis de rival de %s", player_id, exc_info=True)

    dificultad_rival = analisis.dificultad if analisis else None
    prediccion, confianza = predict_for_points(historial, dificultad_rival)
    return PricePrediction(player_id=player_id, prediccion=prediccion, confianza=confianza, rival=analisis)
