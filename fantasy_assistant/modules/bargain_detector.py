"""Módulo 4 — Detector de chollos.

Un "chollo" es un jugador cuyo ratio puntos/precio está muy por encima de
lo normal *para su posición* — comparar un delantero con un portero por
ratio absoluto no tendría sentido (los porteros puntúan y cuestan distinto
por naturaleza), así que la media y desviación típica se calculan dentro
de cada grupo posición, no sobre todo el mercado.

"Puntos" aquí es la media de las últimas 3 jornadas conocidas — la misma
señal de "puntos esperados" que ya usa el optimizador de alineación
(módulo 2), para que el detector sea coherente con el resto de la app en
vez de inventar otra métrica.
"""
from __future__ import annotations

import statistics
from dataclasses import dataclass

from sqlalchemy import select

from fantasy_assistant.config import config
from fantasy_assistant.db.models import PlayerRecord, PointsHistory

# Bajo este precio los ratios se disparan por ruido (un suplente de 100k€
# con 2 puntos en una jornada ya parece un "chollo" de manual) sin ser una
# señal real — de aquí para abajo no se considera para el cálculo.
PRECIO_MINIMO = 500_000


@dataclass
class Bargain:
    player_id: str
    nombre: str
    equipo: str
    posicion: str
    precio: int
    puntos_esperados: float
    ratio: float  # puntos esperados por millón de euros
    zscore: float  # cuántas desviaciones típicas por encima de la media de su posición


def _puntos_esperados_por_jugador(session, source: str) -> dict[str, float]:
    """Media de las últimas 3 jornadas conocidas de cada jugador — misma
    lógica que lineup_optimizer._puntos_esperados_por_jugador, duplicada
    aquí a propósito para no acoplar dos módulos con responsabilidades
    distintas por una función tan pequeña."""
    rows = session.execute(
        select(PointsHistory.player_id, PointsHistory.jornada, PointsHistory.puntos)
        .where(PointsHistory.source == source, PointsHistory.jornada > 0)
        .order_by(PointsHistory.player_id, PointsHistory.jornada.desc())
    ).all()

    por_jugador: dict[str, list[int]] = {}
    for player_id, _jornada, puntos in rows:
        recientes = por_jugador.setdefault(player_id, [])
        if len(recientes) < 3:
            recientes.append(puntos)

    return {pid: sum(vals) / len(vals) for pid, vals in por_jugador.items() if vals}


def detectar_chollos(session, source: str, limit: int = 15) -> list[Bargain]:
    """Jugadores cuyo ratio puntos/precio destaca respecto a los demás de
    su misma posición (z-score >= config.bargain_zscore_threshold),
    ordenados de más a menos chollo."""
    puntos_por_jugador = _puntos_esperados_por_jugador(session, source)
    if not puntos_por_jugador:
        return []

    jugadores = session.execute(
        select(PlayerRecord).where(
            PlayerRecord.source == source,
            PlayerRecord.precio >= PRECIO_MINIMO,
            PlayerRecord.id.in_(puntos_por_jugador.keys()),
        )
    ).scalars().all()

    # Ratio (puntos esperados por millón) agrupado por posición.
    ratios_por_posicion: dict[str, list[tuple[PlayerRecord, float]]] = {}
    for player in jugadores:
        puntos = puntos_por_jugador.get(player.id, 0.0)
        ratio = puntos / (player.precio / 1_000_000)
        ratios_por_posicion.setdefault(player.posicion, []).append((player, ratio))

    chollos: list[Bargain] = []
    for posicion, entradas in ratios_por_posicion.items():
        # Con menos de 5 jugadores en la posición, la media/desviación no
        # es fiable — se descarta ese grupo entero para esta pasada.
        if len(entradas) < 5:
            continue

        valores = [ratio for _, ratio in entradas]
        media = statistics.mean(valores)
        desviacion = statistics.pstdev(valores)
        if desviacion == 0:
            continue

        for player, ratio in entradas:
            zscore = (ratio - media) / desviacion
            if zscore >= config.bargain_zscore_threshold:
                chollos.append(
                    Bargain(
                        player_id=player.id,
                        nombre=player.nombre,
                        equipo=player.equipo,
                        posicion=posicion,
                        precio=player.precio,
                        puntos_esperados=round(puntos_por_jugador.get(player.id, 0.0), 1),
                        ratio=round(ratio, 2),
                        zscore=round(zscore, 2),
                    )
                )

    chollos.sort(key=lambda b: b.zscore, reverse=True)
    return chollos[:limit]
