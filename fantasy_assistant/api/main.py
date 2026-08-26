"""API REST — capa de entrega para la futura app Android (Flutter).

Reutiliza los mismos módulos que el bot de Telegram (price_predictor, etc.),
solo cambia la interfaz de entrega.

Uso local:
    uvicorn fantasy_assistant.api.main:app --reload
"""
from __future__ import annotations

import datetime as dt

from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import Depends, FastAPI, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from fantasy_assistant.api.schemas import DeviceRegisterIn, OptimizedLineupOut, PlayerOut, PrediccionOut
from fantasy_assistant.config import config
from fantasy_assistant.db.database import SessionLocal, init_db
from fantasy_assistant.db.models import DeviceRegistration, PlayerRecord
from fantasy_assistant.jobs.sync_data import sync_once
from fantasy_assistant.modules import price_predictor
from fantasy_assistant.modules.lineup_optimizer import FORMACIONES, LineupError, optimize_lineup

app = FastAPI(title="Fantasy Assistant API", version="0.1.0")

# Sincroniza dentro del propio proceso de la API (en un hilo aparte, vía
# APScheduler) en vez de depender de un segundo servicio + BD compartida:
# más simple de desplegar, sin necesitar un Volume de Railway.
_scheduler = BackgroundScheduler(timezone="UTC")


@app.on_event("startup")
def _startup() -> None:
    init_db()
    _scheduler.add_job(sync_once, "interval", hours=3, next_run_time=dt.datetime.now(dt.timezone.utc))
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
def health() -> dict:
    return {"status": "ok", "fuente_activa": config.fantasy_source}


@app.get("/players", response_model=list[PlayerOut])
def list_players(
    q: str | None = Query(default=None, description="Filtro por nombre (contiene, insensible a mayúsculas)"),
    source: str = Query(default=config.fantasy_source),
    limit: int = Query(default=50, le=200),
    db: Session = Depends(get_db),
) -> list[PlayerRecord]:
    stmt = select(PlayerRecord).where(PlayerRecord.source == source)
    if q:
        stmt = stmt.where(PlayerRecord.nombre.ilike(f"%{q}%"))
    stmt = stmt.limit(limit)
    return db.execute(stmt).scalars().all()


@app.get("/players/{player_id}/prediccion", response_model=PrediccionOut)
def get_prediccion(player_id: str, db: Session = Depends(get_db)) -> PrediccionOut:
    player = db.get(PlayerRecord, player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{player_id}' no encontrado")
    result = price_predictor.predict_player(player_id)
    return PrediccionOut(player_id=result.player_id, prediccion=result.prediccion, confianza=result.confianza)


@app.post("/devices", status_code=201)
def register_device(payload: DeviceRegisterIn, db: Session = Depends(get_db)) -> dict:
    existing = db.execute(
        select(DeviceRegistration).where(DeviceRegistration.fcm_token == payload.fcm_token)
    ).scalar_one_or_none()
    if existing:
        existing.user_id = payload.user_id
    else:
        db.add(DeviceRegistration(fcm_token=payload.fcm_token, user_id=payload.user_id))
    return {"status": "registrado"}


@app.get("/lineup", response_model=OptimizedLineupOut)
def get_lineup(
    presupuesto: int = Query(..., gt=0, description="Presupuesto disponible en euros"),
    formacion: str = Query(default="4-3-3", description=f"Una de: {', '.join(FORMACIONES)}"),
) -> OptimizedLineupOut:
    try:
        result = optimize_lineup(presupuesto=presupuesto, formacion=formacion)
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
