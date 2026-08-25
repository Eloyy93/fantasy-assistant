"""Módulo 2 — Optimizador de alineación.

# TODO fase 2: implementar.
# Input: plantilla del usuario (requiere adapter.login() + adapter.get_user_team())
#   + presupuesto + formación deseada (ej. 4-3-3).
# Problema de mochila con restricción de presupuesto y posición: maximizar
#   la suma de puntos esperados, usando price_predictor / una versión de
#   predicción de puntos como proxy de "puntos esperados" de la próxima jornada.
# Sugerencia: usar `pulp`, o programación dinámica simple (no hace falta
#   una librería pesada).
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class OptimizedLineup:
    formacion: str
    jugadores: list[str]
    puntos_esperados: float


def optimize_lineup(user_id: str, presupuesto: int, formacion: str) -> OptimizedLineup:
    # TODO fase 2
    raise NotImplementedError("lineup_optimizer.optimize_lineup: pendiente fase 2")
