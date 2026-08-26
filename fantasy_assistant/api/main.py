"""API REST — única interfaz de Fantasy Assistant (app Android Flutter).

Uso local:
    uvicorn fantasy_assistant.api.main:app --reload
"""
from __future__ import annotations

import datetime as dt
import unicodedata

from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import Depends, FastAPI, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from fantasy_assistant.api.schemas import (
    DeviceRegisterIn,
    OptimizedLineupOut,
    PlayerHistorialOut,
    PlayerOut,
    PrediccionOut,
    SubscriptionIn,
    TeamMemberIn,
    TeamPlayerOut,
)
from fantasy_assistant.config import config
from fantasy_assistant.datasources import SOURCES, get_data_source
from fantasy_assistant.db.database import SessionLocal, init_db
from fantasy_assistant.db.models import (
    DeviceRegistration,
    DeviceSubscription,
    PlayerRecord,
    PointsHistory,
    PriceHistory,
    TeamPlayer,
)
from fantasy_assistant.jobs.sync_data import sync_once
from fantasy_assistant.modules import price_predictor
from fantasy_assistant.modules.lineup_optimizer import FORMACIONES, LineupError, optimize_lineup

app = FastAPI(title="Fantasy Assistant API", version="0.1.0")

# Sincroniza dentro del propio proceso de la API (en un hilo aparte, vía
# APScheduler) en vez de depender de un segundo servicio + BD compartida:
# más simple de desplegar, sin necesitar un Volume de Railway.
_scheduler = BackgroundScheduler(timezone="UTC")


def _sync_source(source_name: str) -> None:
    sync_once(get_data_source(source_name))


@app.on_event("startup")
def _startup() -> None:
    init_db()
    # Las dos fuentes se sincronizan por separado — si una falla (ej. LaLiga
    # Fantasy caída), no bloquea a la otra. Arrancan escalonadas para no
    # golpear las dos APIs externas a la vez.
    now = dt.datetime.now(dt.timezone.utc)
    for i, source_name in enumerate(SOURCES):
        _scheduler.add_job(
            _sync_source,
            "interval",
            hours=3,
            args=[source_name],
            id=f"sync_{source_name}",
            next_run_time=now + dt.timedelta(seconds=i * 15),
        )
    _scheduler.start()


@app.on_event("shutdown")
def _shutdown() -> None:
    _scheduler.shutdown(wait=False)


def get_db() -> Session:
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict:
    jugadores_por_fuente = {
        source_name: len(db.execute(
            select(PlayerRecord.id).where(PlayerRecord.source == source_name)
        ).scalars().all())
        for source_name in SOURCES
    }
    return {"status": "ok", "jugadores_por_fuente": jugadores_por_fuente}


def _normalizar_busqueda(texto: str) -> str:
    """minúsculas y sin acentos, para que 'alvaro' encuentre 'Álvaro'."""
    sin_acentos = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode("ascii")
    return sin_acentos.lower()


@app.get("/players", response_model=list[PlayerOut])
def list_players(
    q: str | None = Query(default=None, description="Filtro por nombre (contiene, insensible a mayúsculas y acentos)"),
    source: str = Query(default=config.fantasy_source),
    limit: int = Query(default=50, le=200),
    db: Session = Depends(get_db),
) -> list[PlayerRecord]:
    stmt = select(PlayerRecord).where(PlayerRecord.source == source)
    if not q:
        return db.execute(stmt.limit(limit)).scalars().all()

    # SQLite no tiene una forma nativa de ignorar acentos en LIKE, así que
    # filtramos en Python sobre el nombre normalizado (sin acentos). El
    # mercado de una fuente son unos cientos de jugadores, así que traer
    # todos y filtrar en memoria es barato.
    q_normalizada = _normalizar_busqueda(q)
    candidatos = db.execute(stmt).scalars().all()
    coincidencias = [p for p in candidatos if q_normalizada in _normalizar_busqueda(p.nombre)]
    return coincidencias[:limit]


@app.get("/players/{player_id}/prediccion", response_model=PrediccionOut)
def get_prediccion(player_id: str, db: Session = Depends(get_db)) -> PrediccionOut:
    player = db.get(PlayerRecord, player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{player_id}' no encontrado")
    result = price_predictor.predict_player(player_id)
    return PrediccionOut(player_id=result.player_id, prediccion=result.prediccion, confianza=result.confianza)


@app.get("/players/{player_id}/historial", response_model=PlayerHistorialOut)
def get_historial(player_id: str, db: Session = Depends(get_db)) -> PlayerHistorialOut:
    player = db.get(PlayerRecord, player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{player_id}' no encontrado")

    precios = db.execute(
        select(PriceHistory).where(PriceHistory.player_id == player_id).order_by(PriceHistory.fecha)
    ).scalars().all()
    puntos = db.execute(
        select(PointsHistory)
        # jornada <= 0 son entradas sintéticas de LaLiga Fantasy (media de
        # últimos 3 partidos, sin desglose real por jornada — ver
        # LaLigaFantasyAdapter.get_player_points_history) que solo debe
        # consumir el optimizador, no el historial visible al usuario.
        .where(PointsHistory.player_id == player_id, PointsHistory.jornada > 0)
        .order_by(PointsHistory.jornada)
    ).scalars().all()

    return PlayerHistorialOut(
        precios=[{"fecha": str(p.fecha), "precio": p.precio} for p in precios],
        puntos=[{"jornada": p.jornada, "puntos": p.puntos} for p in puntos],
    )


@app.post("/devices", status_code=201)
def register_device(payload: DeviceRegisterIn, db: Session = Depends(get_db)) -> dict:
    existing = db.execute(
        select(DeviceRegistration).where(DeviceRegistration.fcm_token == payload.fcm_token)
    ).scalar_one_or_none()
    if existing:
        existing.user_id = payload.user_id
    else:
        db.add(DeviceRegistration(fcm_token=payload.fcm_token, user_id=payload.user_id))
    db.commit()
    return {"status": "registrado"}


@app.post("/subscriptions", status_code=201)
def subscribe(payload: SubscriptionIn, db: Session = Depends(get_db)) -> dict:
    player = db.get(PlayerRecord, payload.player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{payload.player_id}' no encontrado")

    existente = db.execute(
        select(DeviceSubscription).where(
            DeviceSubscription.fcm_token == payload.fcm_token, DeviceSubscription.player_id == payload.player_id
        )
    ).scalar_one_or_none()
    if not existente:
        db.add(DeviceSubscription(fcm_token=payload.fcm_token, player_id=payload.player_id))
    db.commit()
    return {"status": "suscrito"}


@app.delete("/subscriptions", status_code=204)
def unsubscribe(payload: SubscriptionIn, db: Session = Depends(get_db)) -> None:
    db.execute(
        DeviceSubscription.__table__.delete().where(
            DeviceSubscription.fcm_token == payload.fcm_token, DeviceSubscription.player_id == payload.player_id
        )
    )
    db.commit()


@app.get("/subscriptions", response_model=list[str])
def list_subscriptions(fcm_token: str = Query(...), db: Session = Depends(get_db)) -> list[str]:
    return list(
        db.execute(
            select(DeviceSubscription.player_id).where(DeviceSubscription.fcm_token == fcm_token)
        ).scalars().all()
    )


@app.post("/team", status_code=201)
def add_to_team(payload: TeamMemberIn, db: Session = Depends(get_db)) -> dict:
    player = db.get(PlayerRecord, payload.player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{payload.player_id}' no encontrado")

    existente = db.execute(
        select(TeamPlayer).where(TeamPlayer.device_id == payload.device_id, TeamPlayer.player_id == payload.player_id)
    ).scalar_one_or_none()
    if not existente:
        db.add(TeamPlayer(device_id=payload.device_id, player_id=payload.player_id))
    db.commit()
    return {"status": "añadido"}


@app.delete("/team", status_code=204)
def remove_from_team(payload: TeamMemberIn, db: Session = Depends(get_db)) -> None:
    db.execute(
        TeamPlayer.__table__.delete().where(
            TeamPlayer.device_id == payload.device_id, TeamPlayer.player_id == payload.player_id
        )
    )
    db.commit()


@app.get("/team", response_model=list[TeamPlayerOut])
def get_team(
    device_id: str = Query(...),
    source: str | None = Query(default=None),
    db: Session = Depends(get_db),
) -> list[TeamPlayerOut]:
    """Plantilla del usuario: los jugadores que ha colocado él mismo en el
    campo desde la app (independiente de las notificaciones push), con su
    variación de precio reciente y sus puntos."""
    stmt = select(TeamPlayer.player_id).where(TeamPlayer.device_id == device_id)
    player_ids = db.execute(stmt).scalars().all()
    if not player_ids:
        return []

    resultado: list[TeamPlayerOut] = []
    for player_id in player_ids:
        player = db.get(PlayerRecord, player_id)
        if not player or (source and player.source != source):
            continue

        precios = db.execute(
            select(PriceHistory.precio)
            .where(PriceHistory.player_id == player_id)
            .order_by(PriceHistory.fecha.desc())
            .limit(2)
        ).scalars().all()
        variacion = precios[0] - precios[1] if len(precios) == 2 else None

        puntos_ultima = db.execute(
            select(PointsHistory.puntos)
            .where(PointsHistory.player_id == player_id, PointsHistory.jornada > 0)
            .order_by(PointsHistory.jornada.desc())
            .limit(1)
        ).scalar_one_or_none()

        puntos_temporada = db.execute(
            select(func.coalesce(func.sum(PointsHistory.puntos), 0)).where(
                PointsHistory.player_id == player_id, PointsHistory.jornada > 0
            )
        ).scalar_one()

        resultado.append(
            TeamPlayerOut(
                id=player.id,
                source=player.source,
                nombre=player.nombre,
                equipo=player.equipo,
                posicion=player.posicion,
                precio=player.precio,
                variacion_precio=variacion,
                puntos_ultima_jornada=puntos_ultima,
                puntos_temporada=puntos_temporada,
            )
        )

    return resultado


@app.get("/lineup", response_model=OptimizedLineupOut)
def get_lineup(
    presupuesto: int = Query(..., gt=0, description="Presupuesto disponible en euros"),
    formacion: str = Query(default="4-3-3", description=f"Una de: {', '.join(FORMACIONES)}"),
    source: str = Query(default=config.fantasy_source),
) -> OptimizedLineupOut:
    try:
        result = optimize_lineup(presupuesto=presupuesto, formacion=formacion, source=source)
    except LineupError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return OptimizedLineupOut(
        formacion=result.formacion,
        jugadores=[
            {
                "player_id": j.player_id,
                "nombre": j.nombre,
                "equipo": j.equipo,
                "posicion": j.posicion,
                "precio": j.precio,
                "puntos_esperados": j.puntos_esperados,
            }
            for j in result.jugadores
        ],
        puntos_esperados=result.puntos_esperados,
        presupuesto_usado=result.presupuesto_usado,
    )
