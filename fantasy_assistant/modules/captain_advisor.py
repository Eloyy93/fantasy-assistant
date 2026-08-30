"""Módulo 5 — Capitán óptimo.

De los jugadores que el usuario tiene colocados en el campo (no el
banquillo — el capitán tiene que jugar), calcula quién tiene más
probabilidad de puntuar alto esta jornada, para elegir el multiplicador
de capitán.

La señal base es la misma "puntos esperados" (media de las últimas 3
jornadas) que ya usan el optimizador de alineación (módulo 2) y el
detector de chollos (módulo 4). Cuando la fuente da análisis de rival
(`FantasyDataSource.get_rival_analysis()`, hoy solo Biwenger con
dificultad 0-100), se ajusta esa puntuación hacia arriba si el próximo
rival es flojo y hacia abajo si es duro — mismo principio que el ajuste
de confianza del predictor de precio (módulo 1): el rival nunca decide
el orden por sí solo, solo matiza la señal real de puntos.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

from sqlalchemy import select

from fantasy_assistant.datasources import get_data_source
from fantasy_assistant.db.models import PlayerRecord, PointsHistory, TeamPlayer

logger = logging.getLogger(__name__)

# Cuánto puede mover el rival la puntuación esperada: un rival muy flojo
# (dificultad 0) la sube hasta un 20%, uno muy duro (dificultad 100) la
# baja otro tanto. Dificultad 50 (neutro) no ajusta nada.
RIVAL_SCORE_ADJUST = 0.20


@dataclass
class CaptainCandidate:
    player_id: str
    nombre: str
    equipo: str
    posicion: str
    foto_url: str
    puntos_esperados: float
    score: float
    proximo_rival: str | None
    dificultad_rival: int | None


def _puntos_esperados_por_jugador(session, source: str, player_ids: list[str]) -> dict[str, float]:
    if not player_ids:
        return {}
    rows = session.execute(
        select(PointsHistory.player_id, PointsHistory.jornada, PointsHistory.puntos)
        .where(
            PointsHistory.source == source,
            PointsHistory.jornada > 0,
            PointsHistory.player_id.in_(player_ids),
        )
        .order_by(PointsHistory.player_id, PointsHistory.jornada.desc())
    ).all()

    por_jugador: dict[str, list[int]] = {}
    for player_id, _jornada, puntos in rows:
        recientes = por_jugador.setdefault(player_id, [])
        if len(recientes) < 3:
            recientes.append(puntos)

    return {pid: sum(vals) / len(vals) for pid, vals in por_jugador.items() if vals}


def recomendar_capitan(session, owner_id: str, source: str) -> list[CaptainCandidate]:
    """Candidatos a capitán ordenados de más a menos recomendable.
    Solo tiene en cuenta jugadores colocados en el campo (slot != None) —
    un suplente en el banquillo no puede llevar el brazalete."""
    player_ids = session.execute(
        select(TeamPlayer.player_id)
        .join(PlayerRecord, PlayerRecord.id == TeamPlayer.player_id)
        .where(
            TeamPlayer.owner_id == owner_id,
            TeamPlayer.slot.is_not(None),
            PlayerRecord.source == source,
        )
    ).scalars().all()
    if not player_ids:
        return []

    puntos_por_jugador = _puntos_esperados_por_jugador(session, source, player_ids)

    candidatos: list[CaptainCandidate] = []
    for player_id in player_ids:
        player = session.get(PlayerRecord, player_id)
        if not player:
            continue

        puntos_esperados = puntos_por_jugador.get(player_id, 0.0)

        try:
            analisis = get_data_source(player.source).get_rival_analysis(player.external_id)
        except Exception:
            # El calendario es un extra — si la fuente falla (red,
            # rate-limit...) seguimos con la puntuación base en vez de
            # romper la recomendación entera.
            logger.warning("No se pudo obtener el análisis de rival de %s para el capitán", player_id, exc_info=True)
            analisis = None

        score = puntos_esperados
        proximo_rival = None
        dificultad_rival = None
        if analisis:
            proximo_rival = f"{analisis.rival} ({'Casa' if analisis.casa else 'Fuera'})"
            dificultad_rival = analisis.dificultad
            if analisis.dificultad is not None:
                score = puntos_esperados * (1 + RIVAL_SCORE_ADJUST * (50 - analisis.dificultad) / 50)

        candidatos.append(
            CaptainCandidate(
                player_id=player_id,
                nombre=player.nombre,
                equipo=player.equipo,
                posicion=player.posicion,
                foto_url=player.foto_url,
                puntos_esperados=round(puntos_esperados, 1),
                score=round(score, 2),
                proximo_rival=proximo_rival,
                dificultad_rival=dificultad_rival,
            )
        )

    candidatos.sort(key=lambda c: c.score, reverse=True)
    return candidatos
