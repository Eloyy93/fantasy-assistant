"""Job de sincronización periódica: ingesta datos de la fuente activa a la BD.

Uso:
    python -m fantasy_assistant.jobs.sync_data          # sincroniza una vez
    python -m fantasy_assistant.jobs.sync_data --loop    # cada 2-4h con APScheduler
"""
from __future__ import annotations

import argparse
import datetime as dt
import logging

from sqlalchemy import select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from fantasy_assistant.config import config
from fantasy_assistant.datasources import get_data_source
from fantasy_assistant.datasources.base import FantasyDataSource, Player
from fantasy_assistant.db.database import get_session, init_db
from fantasy_assistant.db.models import PlayerRecord, PointsHistory, PriceHistory

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)


def _composite_id(source: str, external_id: str) -> str:
    return f"{source}:{external_id}"


def sync_once(source: FantasyDataSource | None = None) -> int:
    """Sincroniza jugadores + snapshot de precio + histórico de puntos
    disponible. Devuelve el número de jugadores sincronizados."""
    source = source or get_data_source()
    players: list[Player] = source.get_all_players()
    today = dt.date.today()

    with get_session() as session:
        for p in players:
            record_id = _composite_id(p.source, p.id)

            existing = session.get(PlayerRecord, record_id)
            if existing:
                existing.nombre = p.nombre
                existing.equipo = p.equipo
                existing.posicion = p.posicion
                existing.precio = p.precio
            else:
                session.add(
                    PlayerRecord(
                        id=record_id,
                        source=p.source,
                        external_id=p.id,
                        nombre=p.nombre,
                        equipo=p.equipo,
                        posicion=p.posicion,
                        precio=p.precio,
                    )
                )

            _upsert_price_snapshot(session, record_id, p.source, today, p.precio)

            for entry in source.get_player_points_history(p.id):
                _upsert_points(session, record_id, p.source, entry.jornada, entry.puntos)

    logger.info("Sincronizados %d jugadores (fuente=%s)", len(players), config.fantasy_source)
    return len(players)


def _upsert_price_snapshot(session, player_id: str, source: str, fecha: dt.date, precio: int) -> None:
    stmt = (
        sqlite_insert(PriceHistory)
        .values(player_id=player_id, source=source, fecha=fecha, precio=precio)
        .on_conflict_do_update(
            index_elements=["player_id", "fecha"],
            set_={"precio": precio},
        )
    )
    session.execute(stmt)


def _upsert_points(session, player_id: str, source: str, jornada: int, puntos: int) -> None:
    stmt = (
        sqlite_insert(PointsHistory)
        .values(player_id=player_id, source=source, jornada=jornada, puntos=puntos)
        .on_conflict_do_update(
            index_elements=["player_id", "jornada"],
            set_={"puntos": puntos},
        )
    )
    session.execute(stmt)


def run_scheduler() -> None:
    # TODO fase 3: tras cada sync_once() llamar a modules/alerts.py para
    # comparar contra el snapshot anterior y disparar alertas por Telegram.
    from apscheduler.schedulers.blocking import BlockingScheduler

    scheduler = BlockingScheduler(timezone="UTC")
    scheduler.add_job(sync_once, "interval", hours=3, next_run_time=dt.datetime.now(dt.timezone.utc))
    logger.info("Scheduler iniciado: sincronización cada 3h")
    scheduler.start()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--loop", action="store_true", help="Ejecuta en bucle con APScheduler (cada 3h)")
    args = parser.parse_args()

    init_db()
    if args.loop:
        run_scheduler()
    else:
        sync_once()
