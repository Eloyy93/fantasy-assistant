"""API REST — única interfaz de Fantasy Assistant (app Android Flutter).

Uso local:
    uvicorn fantasy_assistant.api.main:app --reload
"""
from __future__ import annotations

import datetime as dt
import logging
import unicodedata
from urllib.parse import urlparse

import requests
from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from fantasy_assistant.auth import TokenInvalido, resolve_owner_id, verificar_token
from fantasy_assistant.api.schemas import (
    AccountOut,
    BargainOut,
    CaptainOut,
    ChollosPrefIn,
    CompareOut,
    ComparePlayerOut,
    DeviceRegisterIn,
    FormationIn,
    FormationOut,
    OptimizedLineupOut,
    PlayerHistorialOut,
    PlayerOut,
    PrediccionOut,
    RivalAnalysisOut,
    SubscriptionIn,
    TeamMemberIn,
    TeamPlayerOut,
    VincularDispositivoIn,
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
    TeamFormation,
    TeamPlayer,
    User,
)
from fantasy_assistant.jobs.sync_data import sync_all_sources
from fantasy_assistant.modules import bargain_detector, captain_advisor, price_predictor
from fantasy_assistant.modules.lineup_optimizer import FORMACIONES, LineupError, optimize_lineup

logger = logging.getLogger(__name__)

app = FastAPI(title="Fantasy Assistant API", version="0.1.0")

# La app Android no necesita esto (peticiones nativas, sin same-origin
# policy), pero la versión web sí — el navegador bloquea el fetch entre
# orígenes distintos sin esta cabecera. API pública de solo lectura +
# escrituras scoped por device_id/fcm_token (sin sesión ni credenciales),
# así que abrir a cualquier origen no añade superficie de ataque real.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Sincroniza dentro del propio proceso de la API (en un hilo aparte, vía
# APScheduler) en vez de depender de un segundo servicio + BD compartida:
# más simple de desplegar, sin necesitar un Volume de Railway.
_scheduler = BackgroundScheduler(timezone="UTC")


@app.on_event("startup")
def _startup() -> None:
    init_db()
    # sync_all_sources() sincroniza AMBAS fuentes SECUENCIALMENTE, una
    # detrás de otra — no en paralelo. Antes cada fuente era un job aparte
    # arrancado con solo 15s de diferencia, así que sus sync corrían casi
    # enteros al mismo tiempo en hilos distintos: dos escritores
    # machacando la misma BD SQLite a la vez, y LaLiga Fantasy (más
    # lenta, con peticiones por jugador) perdía sistemáticamente la
    # contención de bloqueos frente a Biwenger — se veía como "0
    # jugadores sincronizados durante 20+ min" aunque las peticiones de
    # red en sí funcionaran bien.
    _scheduler.add_job(
        sync_all_sources,
        "interval",
        hours=3,
        id="sync_all_sources",
        next_run_time=dt.datetime.now(dt.timezone.utc),
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


@app.get("/admin/scheduler-status")
def admin_scheduler_status() -> dict:
    """Diagnóstico TEMPORAL: estado real del BackgroundScheduler dentro de
    este proceso — si el job de sync ni siquiera aparece aquí, es que
    _startup() no llegó a programarlo (o el scheduler no está corriendo),
    algo que los logs de Railway no dejan ver sin acceso a la CLI."""
    return {
        "scheduler_running": _scheduler.running,
        "jobs": [
            {
                "id": job.id,
                "next_run_time": str(job.next_run_time),
                "pending": job.pending,
            }
            for job in _scheduler.get_jobs()
        ],
    }


@app.post("/admin/sync-diagnostico")
def admin_sync_diagnostico(source: str = Query(...), limite: int = Query(default=5, le=20)) -> dict:
    """Diagnóstico TEMPORAL: sincroniza una muestra pequeña de [limite]
    jugadores de [source] y devuelve el error real de cada paso en la
    propia respuesta HTTP — sin esto no hay forma de ver por qué el job
    de fondo (jobs/sync_data.py --loop) se queda atascado en producción,
    ya que Railway no expone sus logs sin login interactivo por CLI.
    Quitar una vez diagnosticado el problema real."""
    from fantasy_assistant.datasources import get_data_source

    src = get_data_source(source)
    try:
        jugadores = src.get_all_players()
    except Exception as e:
        return {"paso": "get_all_players", "ok": False, "error": str(e), "tipo": type(e).__name__}

    muestra = jugadores[:limite]
    resultados = []
    for p in muestra:
        entrada: dict = {"id": p.id, "nombre": p.nombre}
        try:
            ph = src.get_player_price_history(p.id)
            entrada["precio_history_ok"] = True
            entrada["precio_history_len"] = len(ph)
        except Exception as e:
            entrada["precio_history_ok"] = False
            entrada["precio_history_error"] = f"{type(e).__name__}: {e}"
        try:
            pth = src.get_player_points_history(p.id)
            entrada["puntos_history_ok"] = True
            entrada["puntos_history_len"] = len(pth)
        except Exception as e:
            entrada["puntos_history_ok"] = False
            entrada["puntos_history_error"] = f"{type(e).__name__}: {e}"
        resultados.append(entrada)

    return {"total_mercado": len(jugadores), "muestra": resultados}


@app.post("/admin/sync-write-diagnostico")
def admin_sync_write_diagnostico(
    source: str = Query(...), limite: int = Query(default=3, le=10), db: Session = Depends(get_db)
) -> dict:
    """Diagnóstico TEMPORAL: intenta escribir en la BD real (a diferencia
    de /admin/sync-diagnostico, que solo prueba la fuente externa) para un
    puñado de jugadores, devolviendo el error real de cada paso — el job
    de sync programado (sync_all_sources) solo LOGUEA sus fallos, no los
    expone en ningún sitio que se pueda consultar sin acceso a los logs de
    Railway."""
    from fantasy_assistant.datasources import get_data_source

    src = get_data_source(source)
    try:
        jugadores = src.get_all_players()[:limite]
    except Exception as e:
        return {"paso": "get_all_players", "ok": False, "error": f"{type(e).__name__}: {e}"}

    resultados = []
    for p in jugadores:
        entrada: dict = {"id": p.id, "nombre": p.nombre}
        try:
            record_id = f"{p.source}:{p.id}"
            existing = db.get(PlayerRecord, record_id)
            if existing:
                existing.nombre = p.nombre
                existing.equipo = p.equipo
                existing.posicion = p.posicion
                existing.precio = p.precio
            else:
                db.add(
                    PlayerRecord(
                        id=record_id, source=p.source, external_id=p.id,
                        nombre=p.nombre, equipo=p.equipo, posicion=p.posicion, precio=p.precio,
                    )
                )
            db.commit()
            entrada["ok"] = True
        except Exception as e:
            db.rollback()
            entrada["ok"] = False
            entrada["error"] = f"{type(e).__name__}: {e}"
        resultados.append(entrada)

    return {"resultados": resultados}


# CDNs de foto conocidos de las fuentes soportadas (ver PlayerRecord.foto_url).
# El proxy solo reenvía estos hosts para que no se convierta en un proxy
# HTTP abierto a cualquier URL.
_PHOTO_HOSTS_PERMITIDOS = {"cdn.biwenger.com", "media.futbolfantasy.com"}


@app.get("/proxy/photo")
def proxy_photo(url: str = Query(...)) -> Response:
    """Reenvía una foto de jugador con cabeceras propias (incluido CORS,
    ya abierto a nivel de app vía CORSMiddleware). La versión web no puede
    cargar estas fotos directamente con Image.network: los CDNs de
    Biwenger/LaLiga Fantasy no llevan cabeceras CORS, así que el navegador
    bloquea la petición — la app Android no tiene este problema (peticiones
    nativas, sin same-origin policy)."""
    host = urlparse(url).hostname
    if host not in _PHOTO_HOSTS_PERMITIDOS:
        raise HTTPException(status_code=400, detail="Host de imagen no permitido")

    try:
        # Sin User-Agent de navegador, cdn.biwenger.com devuelve 403 (bloquea
        # el user-agent por defecto de requests).
        respuesta = requests.get(
            url, timeout=8, headers={"User-Agent": "Mozilla/5.0 (compatible; MasterFantasyBot/1.0)"}
        )
        respuesta.raise_for_status()
    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"No se pudo obtener la imagen: {e}") from e

    return Response(
        content=respuesta.content,
        media_type=respuesta.headers.get("Content-Type", "image/png"),
        headers={"Cache-Control": "public, max-age=86400"},
    )


def _normalizar_busqueda(texto: str) -> str:
    """minúsculas y sin acentos, para que 'alvaro' encuentre 'Álvaro'."""
    sin_acentos = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode("ascii")
    return sin_acentos.lower()


@app.get("/players", response_model=list[PlayerOut])
def list_players(
    q: str | None = Query(default=None, description="Filtro por nombre o equipo (contiene, insensible a mayúsculas y acentos)"),
    source: str = Query(default=config.fantasy_source),
    # le=1000 (no solo 200): la importación de plantilla por captura
    # necesita comparar contra el mercado entero (~600 jugadores) para
    # encontrar coincidencias, no solo una página de resultados.
    limit: int = Query(default=50, le=1000),
    db: Session = Depends(get_db),
) -> list[PlayerRecord]:
    stmt = select(PlayerRecord).where(PlayerRecord.source == source)
    if not q:
        return db.execute(stmt.limit(limit)).scalars().all()

    # SQLite no tiene una forma nativa de ignorar acentos en LIKE, así que
    # filtramos en Python sobre nombre/equipo normalizados (sin acentos).
    # El mercado de una fuente son unos cientos de jugadores, así que traer
    # todos y filtrar en memoria es barato. Busca en nombre O equipo, para
    # que escribir "Barcelona" enseñe a toda la plantilla del equipo.
    q_normalizada = _normalizar_busqueda(q)
    candidatos = db.execute(stmt).scalars().all()
    coincidencias = [
        p
        for p in candidatos
        if q_normalizada in _normalizar_busqueda(p.nombre) or q_normalizada in _normalizar_busqueda(p.equipo)
    ]
    return coincidencias[:limit]


@app.get("/players/{player_id}/prediccion", response_model=PrediccionOut)
def get_prediccion(player_id: str, db: Session = Depends(get_db)) -> PrediccionOut:
    player = db.get(PlayerRecord, player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{player_id}' no encontrado")
    result = price_predictor.predict_player(player_id)
    rival = (
        RivalAnalysisOut(
            rival=result.rival.rival,
            casa=result.rival.casa,
            dificultad=result.rival.dificultad,
            partidos_previos=result.rival.partidos_previos,
            puntos_previos=result.rival.puntos_previos,
            media_previos=result.rival.media_previos,
        )
        if result.rival
        else None
    )
    return PrediccionOut(player_id=result.player_id, prediccion=result.prediccion, confianza=result.confianza, rival=rival)


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


def _build_compare_player(db: Session, player_id: str) -> ComparePlayerOut:
    player = db.get(PlayerRecord, player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{player_id}' no encontrado")

    precios = db.execute(
        select(PriceHistory.precio).where(PriceHistory.player_id == player_id).order_by(PriceHistory.fecha.desc()).limit(2)
    ).scalars().all()
    variacion = precios[0] - precios[1] if len(precios) == 2 else None

    puntos_recientes = db.execute(
        select(PointsHistory.jornada, PointsHistory.puntos)
        .where(PointsHistory.player_id == player_id, PointsHistory.jornada > 0)
        .order_by(PointsHistory.jornada.desc())
        .limit(5)
    ).all()

    puntos_temporada = db.execute(
        select(func.coalesce(func.sum(PointsHistory.puntos), 0)).where(
            PointsHistory.player_id == player_id, PointsHistory.jornada > 0
        )
    ).scalar_one()

    try:
        analisis = get_data_source(player.source).get_rival_analysis(player.external_id)
    except Exception:
        # El próximo rival es un extra "bonito de tener", no crítico — si
        # falla la petición a la fuente (red, rate-limit...) el comparador
        # sigue funcionando sin ese dato en vez de romperse entero.
        logger.warning("No se pudo obtener el análisis de rival de %s", player_id, exc_info=True)
        analisis = None

    proximo_rival = f"{analisis.rival} ({'Casa' if analisis.casa else 'Fuera'})" if analisis else None
    analisis_rival = (
        RivalAnalysisOut(
            rival=analisis.rival,
            casa=analisis.casa,
            dificultad=analisis.dificultad,
            partidos_previos=analisis.partidos_previos,
            puntos_previos=analisis.puntos_previos,
            media_previos=analisis.media_previos,
        )
        if analisis
        else None
    )

    return ComparePlayerOut(
        id=player.id,
        source=player.source,
        nombre=player.nombre,
        equipo=player.equipo,
        posicion=player.posicion,
        precio=player.precio,
        foto_url=player.foto_url,
        variacion_precio=variacion,
        puntos_recientes=[{"jornada": j, "puntos": p} for j, p in reversed(puntos_recientes)],
        puntos_temporada=puntos_temporada,
        proximo_rival=proximo_rival,
        analisis_rival=analisis_rival,
    )


@app.get("/compare", response_model=CompareOut)
def compare_players(a: str = Query(...), b: str = Query(...), db: Session = Depends(get_db)) -> CompareOut:
    return CompareOut(a=_build_compare_player(db, a), b=_build_compare_player(db, b))


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


@app.put("/devices/chollos", status_code=204)
def set_chollos_pref(payload: ChollosPrefIn, db: Session = Depends(get_db)) -> None:
    # Upsert en vez de exigir un registro previo: el registro inicial en
    # POST /devices puede no haber llegado a tiempo (sin red al arrancar
    # la app) y no tiene sentido bloquear esta preferencia por eso.
    device = db.execute(
        select(DeviceRegistration).where(DeviceRegistration.fcm_token == payload.fcm_token)
    ).scalar_one_or_none()
    if not device:
        device = DeviceRegistration(fcm_token=payload.fcm_token)
        db.add(device)
    device.notificar_chollos = payload.activar
    db.commit()


@app.get("/devices/chollos")
def get_chollos_pref(fcm_token: str = Query(...), db: Session = Depends(get_db)) -> dict:
    device = db.execute(
        select(DeviceRegistration).where(DeviceRegistration.fcm_token == fcm_token)
    ).scalar_one_or_none()
    return {"activado": bool(device.notificar_chollos) if device else False}


@app.get("/bargains", response_model=list[BargainOut])
def get_bargains(
    source: str = Query(default=config.fantasy_source),
    limit: int = Query(default=15, le=50),
    db: Session = Depends(get_db),
) -> list[BargainOut]:
    chollos = bargain_detector.detectar_chollos(db, source, limit=limit)
    resultado = []
    for c in chollos:
        player = db.get(PlayerRecord, c.player_id)
        resultado.append(
            BargainOut(
                id=c.player_id,
                nombre=c.nombre,
                equipo=c.equipo,
                posicion=c.posicion,
                precio=c.precio,
                puntos_esperados=c.puntos_esperados,
                ratio=c.ratio,
                zscore=c.zscore,
                foto_url=player.foto_url if player else "",
            )
        )
    return resultado


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


@app.get("/subscriptions/detalle", response_model=list[PlayerOut])
def list_subscriptions_detalle(fcm_token: str = Query(...), db: Session = Depends(get_db)) -> list[PlayerRecord]:
    """Ficha completa de cada jugador al que este dispositivo está
    suscrito — usado por la pantalla "Notificaciones" para poder
    mostrar nombre/foto en vez de solo el id y dejar desactivar cada
    una sin tener que ir jugador por jugador."""
    player_ids = db.execute(
        select(DeviceSubscription.player_id).where(DeviceSubscription.fcm_token == fcm_token)
    ).scalars().all()
    if not player_ids:
        return []
    jugadores = db.execute(select(PlayerRecord).where(PlayerRecord.id.in_(player_ids))).scalars().all()
    # Mantiene el orden de suscripción en vez del que devuelva el IN().
    por_id = {p.id: p for p in jugadores}
    return [por_id[pid] for pid in player_ids if pid in por_id]


@app.get("/account/me", response_model=AccountOut)
def account_me(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> AccountOut:
    """Perfil de la sesión iniciada (token de Google verificado). 401 si no
    hay token o no es válido — a diferencia del resto de endpoints de
    "Mi plantilla", este SÍ exige haber iniciado sesión."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Falta la cabecera Authorization")
    try:
        claims = verificar_token(authorization[7:].strip())
    except TokenInvalido as e:
        raise HTTPException(status_code=401, detail=str(e)) from e

    uid = claims["uid"]
    usuario = db.get(User, uid)
    if usuario is None:
        usuario = User(id=uid, email=claims.get("email"), nombre=claims.get("name"), foto_url=claims.get("picture"))
        db.add(usuario)
        db.commit()
    return AccountOut(id=usuario.id, email=usuario.email, nombre=usuario.nombre, foto_url=usuario.foto_url)


@app.post("/account/vincular-dispositivo", status_code=204)
def vincular_dispositivo(
    payload: VincularDispositivoIn,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> None:
    """Traspasa la plantilla y formación guardadas con el device_id local
    (uso sin sesión) a la cuenta que acaba de iniciar sesión — se llama una
    vez, justo después del primer login, si el dispositivo ya tenía datos.
    Si la cuenta YA tenía su propia plantilla, esos jugadores del
    dispositivo simplemente no se traspasan (no se sobrescribe nada de la
    cuenta) — la app debe avisar de esto antes de llamar aquí."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Falta la cabecera Authorization")
    try:
        claims = verificar_token(authorization[7:].strip())
    except TokenInvalido as e:
        raise HTTPException(status_code=401, detail=str(e)) from e

    device_owner_id = f"device:{payload.device_id}"
    user_owner_id = f"user:{claims['uid']}"

    ya_ocupados_team = {
        (source, player_id)
        for source, player_id in db.execute(
            select(TeamPlayer.source, TeamPlayer.player_id).where(TeamPlayer.owner_id == user_owner_id)
        ).all()
    }
    for fila in db.execute(select(TeamPlayer).where(TeamPlayer.owner_id == device_owner_id)).scalars().all():
        if (fila.source, fila.player_id) in ya_ocupados_team:
            continue
        fila.owner_id = user_owner_id
        # Al banquillo, no al campo — su antiguo slot podría estar ya
        # ocupado por otro jugador en la plantilla de la cuenta, y
        # colocarlo a la fuerza violaría el UNIQUE(owner_id, slot,
        # source). El usuario los reordena a mano tras vincular.
        fila.slot = None

    formaciones_existentes = {
        source
        for (source,) in db.execute(
            select(TeamFormation.source).where(TeamFormation.owner_id == user_owner_id)
        ).all()
    }
    for fila in db.execute(select(TeamFormation).where(TeamFormation.owner_id == device_owner_id)).scalars().all():
        if fila.source in formaciones_existentes:
            continue
        fila.owner_id = user_owner_id

    db.commit()


@app.post("/team", status_code=201)
def add_to_team(
    payload: TeamMemberIn,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict:
    owner_id = resolve_owner_id(db, payload.device_id, authorization)
    player = db.get(PlayerRecord, payload.player_id)
    if not player:
        raise HTTPException(status_code=404, detail=f"Jugador '{payload.player_id}' no encontrado")

    if payload.slot:
        # Si el hueco ya lo ocupaba otro jugador DE LA MISMA FUENTE, no lo
        # borramos de la plantilla — lo mandamos al banquillo (slot=None),
        # al estilo Futbin: "colocar aquí" nunca hace desaparecer a nadie.
        # Filtrar por source es imprescindible: los nombres de slot
        # ("DEF2", "MED1"...) se repiten entre Biwenger y LaLiga Fantasy.
        ocupante = db.execute(
            select(TeamPlayer).where(
                TeamPlayer.owner_id == owner_id,
                TeamPlayer.slot == payload.slot,
                TeamPlayer.source == player.source,
            )
        ).scalar_one_or_none()
        if ocupante and ocupante.player_id != payload.player_id:
            ocupante.slot = None

    existente = db.execute(
        select(TeamPlayer).where(TeamPlayer.owner_id == owner_id, TeamPlayer.player_id == payload.player_id)
    ).scalar_one_or_none()
    if existente:
        existente.slot = payload.slot
    else:
        db.add(TeamPlayer(owner_id=owner_id, player_id=payload.player_id, source=player.source, slot=payload.slot))
    db.commit()
    return {"status": "añadido"}


@app.delete("/team", status_code=204)
def remove_from_team(
    payload: TeamMemberIn,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> None:
    owner_id = resolve_owner_id(db, payload.device_id, authorization)
    db.execute(
        TeamPlayer.__table__.delete().where(
            TeamPlayer.owner_id == owner_id, TeamPlayer.player_id == payload.player_id
        )
    )
    db.commit()


@app.delete("/team/clear", status_code=204)
def clear_team(
    device_id: str = Query(...),
    source: str = Query(...),
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> None:
    """Vacía toda la plantilla de una fuente (banquillo + huecos). No toca
    la formación elegida ni la plantilla de la otra fuente."""
    owner_id = resolve_owner_id(db, device_id, authorization)
    player_ids_de_la_fuente = db.execute(
        select(PlayerRecord.id).where(PlayerRecord.source == source)
    ).scalars().all()
    db.execute(
        TeamPlayer.__table__.delete().where(
            TeamPlayer.owner_id == owner_id, TeamPlayer.player_id.in_(player_ids_de_la_fuente)
        )
    )
    db.commit()


@app.get("/team/contains")
def team_contains(
    device_id: str = Query(...),
    player_id: str = Query(...),
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict:
    """Consulta ligera para el botón "añadir a mi plantilla" de la ficha de
    un jugador, sin traer toda la plantilla solo para comprobar uno."""
    owner_id = resolve_owner_id(db, device_id, authorization)
    existente = db.execute(
        select(TeamPlayer).where(TeamPlayer.owner_id == owner_id, TeamPlayer.player_id == player_id)
    ).scalar_one_or_none()
    return {"en_plantilla": existente is not None}


@app.get("/team", response_model=list[TeamPlayerOut])
def get_team(
    device_id: str = Query(...),
    source: str | None = Query(default=None),
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> list[TeamPlayerOut]:
    """Plantilla del usuario: los jugadores que ha colocado él mismo en el
    campo desde la app (independiente de las notificaciones push), con su
    variación de precio reciente y sus puntos."""
    owner_id = resolve_owner_id(db, device_id, authorization)
    stmt = select(TeamPlayer.player_id, TeamPlayer.slot).where(TeamPlayer.owner_id == owner_id)
    filas = db.execute(stmt).all()
    if not filas:
        return []

    resultado: list[TeamPlayerOut] = []
    for player_id, slot in filas:
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
                slot=slot,
                foto_url=player.foto_url,
            )
        )

    return resultado


@app.get("/team/capitan", response_model=list[CaptainOut])
def get_capitan(
    device_id: str = Query(...),
    source: str = Query(default=config.fantasy_source),
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> list[CaptainOut]:
    """Módulo 5 — de los jugadores colocados en el campo (no el
    banquillo), quién tiene más probabilidad de puntuar alto esta
    jornada, para elegir el multiplicador de capitán."""
    owner_id = resolve_owner_id(db, device_id, authorization)
    candidatos = captain_advisor.recomendar_capitan(db, owner_id, source)
    return [
        CaptainOut(
            id=c.player_id,
            nombre=c.nombre,
            equipo=c.equipo,
            posicion=c.posicion,
            foto_url=c.foto_url,
            puntos_esperados=c.puntos_esperados,
            score=c.score,
            proximo_rival=c.proximo_rival,
            dificultad_rival=c.dificultad_rival,
        )
        for c in candidatos
    ]


@app.get("/team/formacion", response_model=FormationOut)
def get_formacion(
    device_id: str = Query(...),
    source: str = Query(...),
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> FormationOut:
    owner_id = resolve_owner_id(db, device_id, authorization)
    formacion = db.execute(
        select(TeamFormation.formacion).where(TeamFormation.owner_id == owner_id, TeamFormation.source == source)
    ).scalar_one_or_none()
    return FormationOut(formacion=formacion or "4-3-3")


@app.put("/team/formacion", status_code=204)
def set_formacion(
    payload: FormationIn,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> None:
    if payload.formacion not in FORMACIONES:
        raise HTTPException(status_code=400, detail=f"Formación '{payload.formacion}' no soportada")

    owner_id = resolve_owner_id(db, payload.device_id, authorization)
    existente = db.execute(
        select(TeamFormation).where(TeamFormation.owner_id == owner_id, TeamFormation.source == payload.source)
    ).scalar_one_or_none()
    if existente:
        existente.formacion = payload.formacion
    else:
        db.add(TeamFormation(owner_id=owner_id, source=payload.source, formacion=payload.formacion))
    db.commit()


@app.get("/team/recomendados", response_model=list[TeamPlayerOut])
def get_recomendados(
    source: str = Query(...),
    posicion: str = Query(...),
    excluir: str = Query(default="", description="ids separados por coma a excluir"),
    limit: int = Query(default=8, le=30),
    db: Session = Depends(get_db),
) -> list[TeamPlayerOut]:
    """Mejores jugadores de una posición por puntos de temporada, para
    recomendar al tocar un hueco vacío en el campo (estilo Futbin)."""
    excluidos = {pid for pid in excluir.split(",") if pid}

    puntos_totales = (
        select(PointsHistory.player_id, func.sum(PointsHistory.puntos).label("total"))
        .where(PointsHistory.jornada > 0)
        .group_by(PointsHistory.player_id)
        .subquery()
    )
    total_col = func.coalesce(puntos_totales.c.total, 0)
    stmt = (
        select(PlayerRecord, total_col)
        .outerjoin(puntos_totales, puntos_totales.c.player_id == PlayerRecord.id)
        .where(PlayerRecord.source == source, PlayerRecord.posicion == posicion)
        .order_by(total_col.desc())
        .limit(limit + len(excluidos))
    )

    resultado: list[TeamPlayerOut] = []
    for player, puntos_temporada in db.execute(stmt).all():
        if player.id in excluidos:
            continue
        if len(resultado) >= limit:
            break

        puntos_ultima = db.execute(
            select(PointsHistory.puntos)
            .where(PointsHistory.player_id == player.id, PointsHistory.jornada > 0)
            .order_by(PointsHistory.jornada.desc())
            .limit(1)
        ).scalar_one_or_none()

        resultado.append(
            TeamPlayerOut(
                id=player.id,
                source=player.source,
                nombre=player.nombre,
                equipo=player.equipo,
                posicion=player.posicion,
                precio=player.precio,
                variacion_precio=None,
                puntos_ultima_jornada=puntos_ultima,
                puntos_temporada=puntos_temporada,
                slot=None,
                foto_url=player.foto_url,
            )
        )

    return resultado


@app.get("/lineup", response_model=OptimizedLineupOut)
def get_lineup(
    presupuesto: int = Query(..., gt=0, description="Presupuesto disponible en euros"),
    formacion: str = Query(default="4-3-3", description=f"Una de: {', '.join(FORMACIONES)}"),
    source: str = Query(default=config.fantasy_source),
    fijos: str = Query(default="", description="Ids de jugadores que ya se quieren tener sí o sí, separados por comas"),
) -> OptimizedLineupOut:
    ids_fijos = [f for f in fijos.split(",") if f]
    try:
        result = optimize_lineup(presupuesto=presupuesto, formacion=formacion, source=source, fijos=ids_fijos)
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
                "foto_url": j.foto_url,
            }
            for j in result.jugadores
        ],
        puntos_esperados=result.puntos_esperados,
        presupuesto_usado=result.presupuesto_usado,
    )
