"""Módulo 2 — Optimizador de alineación.

Dado un presupuesto y una formación (ej. "4-3-3"), elige entre TODOS los
jugadores del mercado — agrupados por posición — la combinación que
maximiza la suma de puntos esperados sin superar el presupuesto.

Es un problema de mochila por grupos: cada posición es un grupo del que hay
que elegir exactamente N jugadores (N = lo que pida la formación), y el
"peso" de cada jugador es su precio. Se resuelve así:
  1. Por cada grupo/posición, un DP de mochila con la restricción de
     "elegir exactamente N" calcula, para cada presupuesto discretizado
     posible, la mejor puntuación alcanzable gastando como mucho eso.
  2. Un segundo DP combina los grupos, repartiendo el presupuesto total
     entre posiciones para maximizar la suma de puntos.

"Puntos esperados" de un jugador = media de sus últimas 3 jornadas
conocidas (mismo dato que usa el módulo 1 como "reciente").

# TODO fase 2b: usar la plantilla real del usuario (adapter.login() +
# get_user_team()) para no recomendar comprar jugadores que ya tiene, y
# para que el presupuesto por defecto sea su saldo real en vez de un valor
# manual.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import select

from fantasy_assistant.config import config
from fantasy_assistant.db.database import get_session
from fantasy_assistant.db.models import PlayerRecord, PointsHistory

# Cuántas posiciones de cada tipo lleva cada formación estándar (el portero,
# 1, es siempre implícito y no hace falta escribirlo en la formación).
FORMACIONES = {
    "4-3-3": {"DEF": 4, "MED": 3, "DEL": 3},
    "4-4-2": {"DEF": 4, "MED": 4, "DEL": 2},
    "3-4-3": {"DEF": 3, "MED": 4, "DEL": 3},
    "3-5-2": {"DEF": 3, "MED": 5, "DEL": 2},
    "5-3-2": {"DEF": 5, "MED": 3, "DEL": 2},
    "5-4-1": {"DEF": 5, "MED": 4, "DEL": 1},
}

# Presupuesto se discretiza en "cubos" para que la mochila sea resoluble:
# demasiados euros exactos = demasiados estados. 50.000€ es un compromiso
# razonable entre precisión y velocidad para precios típicos de fantasy.
BUCKET_SIZE = 50_000
MAX_BUCKETS = 1500  # tope de seguridad; agranda el cubo si hiciera falta


@dataclass
class LineupPlayer:
    player_id: str
    nombre: str
    equipo: str
    posicion: str
    precio: int
    puntos_esperados: float
    foto_url: str = ""


@dataclass
class OptimizedLineup:
    formacion: str
    jugadores: list[LineupPlayer] = field(default_factory=list)
    puntos_esperados: float = 0.0
    presupuesto_usado: int = 0


class LineupError(ValueError):
    pass


def _puntos_esperados_por_jugador(session, source: str) -> dict[str, float]:
    """Media de las últimas 3 jornadas conocidas de cada jugador."""
    rows = session.execute(
        select(PointsHistory.player_id, PointsHistory.jornada, PointsHistory.puntos)
        .where(PointsHistory.source == source)
        .order_by(PointsHistory.player_id, PointsHistory.jornada.desc())
    ).all()

    por_jugador: dict[str, list[int]] = {}
    for player_id, _jornada, puntos in rows:
        recientes = por_jugador.setdefault(player_id, [])
        if len(recientes) < 3:
            recientes.append(puntos)

    return {pid: sum(vals) / len(vals) for pid, vals in por_jugador.items() if vals}


def _candidatos_por_posicion(
    session, source: str, formacion_counts: dict[str, int]
) -> dict[str, list[LineupPlayer]]:
    puntos_por_jugador = _puntos_esperados_por_jugador(session, source)

    posiciones = ["POR", *formacion_counts.keys()]
    candidatos: dict[str, list[LineupPlayer]] = {pos: [] for pos in posiciones}

    rows = session.execute(
        select(PlayerRecord).where(PlayerRecord.source == source, PlayerRecord.posicion.in_(posiciones))
    ).scalars().all()

    for p in rows:
        if p.precio <= 0:
            continue
        candidatos[p.posicion].append(
            LineupPlayer(
                player_id=p.id,
                nombre=p.nombre,
                equipo=p.equipo,
                posicion=p.posicion,
                precio=p.precio,
                puntos_esperados=puntos_por_jugador.get(p.id, 0.0),
                foto_url=p.foto_url,
            )
        )

    return candidatos


def _mochila_grupo(candidatos: list[LineupPlayer], n: int, max_bucket: int, bucket_size: int) -> list[tuple[float, list[int]]]:
    """DP de mochila 0/1 con restricción "elegir exactamente n". Devuelve,
    para cada presupuesto en cubos de 0..max_bucket, la mejor puntuación y
    los índices (en `candidatos`) elegidos para lograrla.

    Guarda el histórico completo de la tabla tras cada ítem procesado
    (dp_history) para poder reconstruir la selección sin ambigüedad: la
    alternativa de "un único puntero al último ítem que mejoró cada celda"
    se rompe en cuanto un ítem posterior vuelve a mejorar una celda de la
    que dependía una reconstrucción anterior — puede acabar eligiendo el
    mismo jugador dos veces.
    """
    NEG_INF = float("-inf")
    base = [[0.0 if j == 0 else NEG_INF for _ in range(max_bucket + 1)] for j in range(n + 1)]
    dp_history = [base]

    for jugador in candidatos:
        coste = jugador.precio // bucket_size
        anterior = dp_history[-1]
        if coste > max_bucket:
            # No cabe en el presupuesto ni solo: descartarlo, nunca recortarlo
            # al máximo del cubo (eso lo haría parecer gratis).
            dp_history.append(anterior)
            continue
        nuevo = [row[:] for row in anterior]
        for j in range(1, n + 1):
            fila_prev = anterior[j - 1]
            for b in range(coste, max_bucket + 1):
                val_prev = fila_prev[b - coste]
                if val_prev == NEG_INF:
                    continue
                candidato_valor = val_prev + jugador.puntos_esperados
                if candidato_valor > nuevo[j][b]:
                    nuevo[j][b] = candidato_valor
        dp_history.append(nuevo)

    dp_final = dp_history[-1]
    resultado: list[tuple[float, list[int]]] = []
    for b in range(max_bucket + 1):
        valor = dp_final[n][b]
        if valor == NEG_INF:
            resultado.append((NEG_INF, []))
            continue
        resultado.append((valor, _reconstruir(candidatos, dp_history, n, b, bucket_size)))
    return resultado


def _reconstruir(candidatos: list[LineupPlayer], dp_history: list, j: int, b: int, bucket_size: int) -> list[int]:
    elegidos: list[int] = []
    idx = len(candidatos)
    while idx > 0 and j > 0:
        item = candidatos[idx - 1]
        if dp_history[idx][j][b] != dp_history[idx - 1][j][b]:
            elegidos.append(idx - 1)
            j -= 1
            b -= item.precio // bucket_size
        idx -= 1
    return elegidos


def optimize_lineup(presupuesto: int, formacion: str = "4-3-3", source: str | None = None) -> OptimizedLineup:
    formacion = formacion.strip()
    if formacion not in FORMACIONES:
        raise LineupError(f"Formación '{formacion}' no soportada. Usa una de: {', '.join(FORMACIONES)}")
    if presupuesto <= 0:
        raise LineupError("El presupuesto debe ser mayor que 0")

    source = source or config.fantasy_source
    formacion_counts = FORMACIONES[formacion]
    grupos = {"POR": 1, **formacion_counts}

    bucket_size = BUCKET_SIZE
    max_bucket = presupuesto // bucket_size
    if max_bucket > MAX_BUCKETS:
        bucket_size = presupuesto // MAX_BUCKETS + 1
        max_bucket = presupuesto // bucket_size

    with get_session() as session:
        candidatos_por_posicion = _candidatos_por_posicion(session, source, formacion_counts)

    for posicion, n in grupos.items():
        if len(candidatos_por_posicion.get(posicion, [])) < n:
            raise LineupError(
                f"No hay suficientes jugadores de '{posicion}' en el mercado ({len(candidatos_por_posicion.get(posicion, []))} < {n})"
            )

    # Resuelve cada grupo/posición por separado, luego combina repartiendo
    # presupuesto entre grupos para maximizar la suma total de puntos.
    tablas_grupo: dict[str, list[tuple[float, list[int]]]] = {
        posicion: _mochila_grupo(candidatos_por_posicion[posicion], n, max_bucket, bucket_size)
        for posicion, n in grupos.items()
    }

    NEG_INF = float("-inf")
    posiciones = list(grupos.keys())

    # overall[b] = (mejor puntuación combinando los grupos ya procesados
    # gastando <= b, [(posicion, presupuesto_asignado), ...])
    overall: list[tuple[float, list[tuple[str, int]]]] = [
        (tablas_grupo[posiciones[0]][b][0], [(posiciones[0], b)]) for b in range(max_bucket + 1)
    ]

    for posicion in posiciones[1:]:
        tabla = tablas_grupo[posicion]
        nuevo: list[tuple[float, list[tuple[str, int]]]] = [(NEG_INF, []) for _ in range(max_bucket + 1)]
        for b in range(max_bucket + 1):
            mejor_valor, mejor_reparto = NEG_INF, []
            for b1 in range(b + 1):
                b2 = b - b1
                v1, reparto1 = overall[b1]
                v2, _ = tabla[b2]
                if v1 == NEG_INF or v2 == NEG_INF:
                    continue
                if v1 + v2 > mejor_valor:
                    mejor_valor = v1 + v2
                    mejor_reparto = [*reparto1, (posicion, b2)]
            nuevo[b] = (mejor_valor, mejor_reparto)
        overall = nuevo

    mejor_b = max(range(max_bucket + 1), key=lambda b: overall[b][0])
    mejor_valor, reparto = overall[mejor_b]
    if mejor_valor == NEG_INF:
        raise LineupError("No se pudo formar una alineación completa con ese presupuesto")

    jugadores: list[LineupPlayer] = []
    presupuesto_usado = 0
    for posicion, b_asignado in reparto:
        _, indices = tablas_grupo[posicion][b_asignado]
        for idx in indices:
            jugador = candidatos_por_posicion[posicion][idx]
            jugadores.append(jugador)
            presupuesto_usado += jugador.precio

    return OptimizedLineup(
        formacion=formacion,
        jugadores=jugadores,
        puntos_esperados=round(sum(j.puntos_esperados for j in jugadores), 2),
        presupuesto_usado=presupuesto_usado,
    )
