"""Job de sincronización periódica: ingesta datos de la fuente activa a la BD.

Uso:
    python -m fantasy_assistant.jobs.sync_data          # sincroniza una vez
    python -m fantasy_assistant.jobs.sync_data --loop    # cada 2-4h con APScheduler
"""
from __future__ import annotations

import argparse
import datetime as dt
import logging
import random

from sqlalchemy import select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from fantasy_assistant.config import config
from fantasy_assistant.datasources import SOURCES, get_data_source
from fantasy_assistant.datasources.base import FantasyDataSource, Player
from fantasy_assistant.db.database import get_session, init_db
from fantasy_assistant.db.models import (
    BargainState,
    DeviceRegistration,
    DeviceSubscription,
    PlayerRecord,
    PointsHistory,
    PriceHistory,
)
from fantasy_assistant.modules import alerts, bargain_detector
from fantasy_assistant.notifications import fcm

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)


def _composite_id(source: str, external_id: str) -> str:
    return f"{source}:{external_id}"


def sync_once(source: FantasyDataSource | None = None) -> int:
    """Sincroniza jugadores + snapshot de precio + histórico de puntos
    disponible. Devuelve el número de jugadores sincronizados."""
    source = source or get_data_source()
    players: list[Player] = source.get_all_players()
    # Mezclar el orden: algunas fuentes (Biwenger) hacen una petición extra
    # por jugador para el histórico de precio y pueden toparse con
    # rate-limiting a mitad de sync, dejando de intentarlo con los que
    # queden por delante (ver BiwengerAdapter.get_player_price_history). Sin
    # mezclar, siempre serían los mismos jugadores (los primeros del listado)
    # los que consiguen histórico y los últimos los que nunca lo consiguen.
    # Mezclando, con varias sincronizaciones (cada 3h) se acaba cubriendo a
    # todos aunque cada una individual no llegue a completarlos.
    random.shuffle(players)
    today = dt.date.today()
    disparadas: list[alerts.Alert] = []

    fallidos = 0
    with get_session() as session:
        for p in players:
            record_id = _composite_id(p.source, p.id)

            try:
                # Peticiones de red PRIMERO, antes de tocar la sesión de
                # escritura. Si se pidieran después de un session.add/execute,
                # la transacción de escritura quedaría abierta durante toda
                # la llamada HTTP (lenta en algunas fuentes, ej. LaLiga
                # Fantasy hace una petición por jugador) y bloquearía a
                # cualquier otro escritor — visto en producción como
                # peticiones de la app (guardar plantilla, formación...)
                # colgadas hasta el busy_timeout de SQLite (30s).
                precio_history = source.get_player_price_history(p.id)
                puntos_history = source.get_player_points_history(p.id)

                existing = session.get(PlayerRecord, record_id)
                if existing:
                    alert = alerts.check_price_change(record_id, p.nombre, existing.precio, p.precio)
                    if alert:
                        disparadas.append(alert)
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

                # Histórico extra que algunas fuentes puedan ofrecer (ej.
                # LaLiga Fantasy da hasta 30 días de precios en la misma
                # petición que el listado de jugadores). Biwenger devuelve
                # lista vacía aquí.
                for punto in precio_history:
                    _upsert_price_snapshot(session, record_id, p.source, dt.date.fromisoformat(punto.fecha), punto.precio)

                for entry in puntos_history:
                    _upsert_points(session, record_id, p.source, entry.jornada, entry.puntos)

                # Commit por jugador en vez de uno solo al final: con fuentes
                # lentas (ej. LaLiga Fantasy, ~6 min por el scraping jornada a
                # jornada) una única transacción larga bloquearía cualquier
                # otra escritura (registro de dispositivo, suscripción...)
                # durante todo ese tiempo — visto en producción como
                # "database is locked".
                session.commit()
            except Exception:
                # Un jugador con datos raros o un fallo de red puntual (ej.
                # get_player_points_history de LaLiga Fantasy, que hace una
                # petición HTTP por jugador) no debe tirar la sincronización
                # entera — visto en producción: Biwenger se quedó atascado a
                # mitad de sync sin seguir con el resto. Se salta ese
                # jugador y sigue con los demás.
                session.rollback()
                fallidos += 1
                logger.exception("Fallo sincronizando %s — se salta y se sigue", record_id)

        if fallidos:
            logger.warning("%d/%d jugadores fallaron al sincronizar (fuente=%s)", fallidos, len(players), config.fantasy_source)

    if disparadas:
        with get_session() as session:
            _send_alerts(session, disparadas)

    if players:
        with get_session() as session:
            _detectar_y_notificar_chollos(session, players[0].source)

    fuente = players[0].source if players else config.fantasy_source
    logger.info("Sincronizados %d jugadores (fuente=%s)", len(players), fuente)
    return len(players)


def _send_alerts(session, alertas_disparadas: list[alerts.Alert]) -> None:
    # Push (FCM) únicamente a los dispositivos suscritos a ese jugador
    # concreto (gestionado desde la app, ver POST/DELETE /subscriptions).
    invalid_tokens: set[str] = set()
    enviadas = 0
    for alert in alertas_disparadas:
        tokens = session.execute(
            select(DeviceSubscription.fcm_token).where(DeviceSubscription.player_id == alert.player_id)
        ).scalars().all()
        if not tokens:
            continue
        invalid_tokens.update(fcm.send_alerts([alert], list(tokens)))
        enviadas += 1
        logger.info("Alerta de %s enviada a %d dispositivos suscritos", alert.player_id, len(tokens))

    if invalid_tokens:
        session.execute(DeviceRegistration.__table__.delete().where(DeviceRegistration.fcm_token.in_(invalid_tokens)))
        session.execute(DeviceSubscription.__table__.delete().where(DeviceSubscription.fcm_token.in_(invalid_tokens)))

    if enviadas:
        logger.info("%d/%d alertas tenían al menos un dispositivo suscrito", enviadas, len(alertas_disparadas))


def _detectar_y_notificar_chollos(session, source: str) -> None:
    """Módulo 4 — detecta chollos (ratio puntos/precio anómalo para su
    posición) y notifica solo los que *acaban de convertirse* en chollo,
    a los dispositivos que hayan activado ese aviso (independiente de las
    suscripciones por jugador — el punto de un chollo es descubrir a
    alguien que aún no seguías)."""
    chollos_actuales = bargain_detector.detectar_chollos(session, source)
    ids_actuales = {c.player_id for c in chollos_actuales}

    estados_previos = {
        s.player_id: s.es_chollo
        for s in session.execute(select(BargainState)).scalars().all()
    }

    nuevos = [c for c in chollos_actuales if not estados_previos.get(c.player_id, False)]

    # Actualiza el estado de TODOS los que aparecieron esta vez (nuevos y
    # los que ya lo eran) y de los que dejaron de serlo, para que la
    # próxima sincronización sepa distinguir "sigue siendo chollo" de
    # "chollo nuevo".
    for player_id, era_chollo in estados_previos.items():
        if era_chollo and player_id not in ids_actuales:
            session.merge(BargainState(player_id=player_id, es_chollo=False))
    for chollo in chollos_actuales:
        session.merge(BargainState(player_id=chollo.player_id, es_chollo=True))
    session.commit()

    if not nuevos:
        return

    tokens = session.execute(
        select(DeviceRegistration.fcm_token).where(DeviceRegistration.notificar_chollos.is_(True))
    ).scalars().all()
    if not tokens:
        logger.info("%d chollo(s) nuevo(s) en %s, pero nadie tiene activadas las notificaciones", len(nuevos), source)
        return

    alertas_chollo = [
        alerts.Alert(
            player_id=c.player_id,
            mensaje=f"Chollo: {c.nombre} ({c.equipo}, {c.posicion}) — {c.puntos_esperados} pts esperados por solo {c.precio / 1_000_000:.2f} M€",
        )
        for c in nuevos
    ]
    invalid_tokens = fcm.send_alerts(alertas_chollo, list(tokens))
    if invalid_tokens:
        session.execute(DeviceRegistration.__table__.delete().where(DeviceRegistration.fcm_token.in_(invalid_tokens)))
        session.execute(DeviceSubscription.__table__.delete().where(DeviceSubscription.fcm_token.in_(invalid_tokens)))
        session.commit()

    logger.info("%d chollo(s) nuevo(s) en %s, notificados a %d dispositivos", len(nuevos), source, len(tokens))


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


def sync_all_sources() -> None:
    """Sincroniza TODAS las fuentes soportadas (Biwenger y LaLiga Fantasy),
    no solo la de FANTASY_SOURCE — la app deja elegir la fuente desde la
    pestaña de "Mi plantilla", así que ambas necesitan datos reales."""
    for nombre in SOURCES:
        try:
            sync_once(get_data_source(nombre))
        except Exception:
            logger.exception("Fallo sincronizando la fuente %s — se salta y se sigue con las demás", nombre)


def run_scheduler() -> None:
    from apscheduler.schedulers.blocking import BlockingScheduler

    scheduler = BlockingScheduler(timezone="UTC")
    scheduler.add_job(sync_all_sources, "interval", hours=3, next_run_time=dt.datetime.now(dt.timezone.utc))
    logger.info("Scheduler iniciado: sincronización cada 3h (todas las fuentes: %s)", ", ".join(SOURCES))
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
