"""Bot de Telegram — interfaz de usuario de Fantasy Assistant.

Comandos v1:
    /fuente biwenger | laligafantasy   - elige la fuente de datos (por usuario)
    /prediccion <jugador>              - módulo 1 (predictor de precio)
    /alineacion <presupuesto> [formación] - módulo 2 (optimizador de alineación)
    /alertas on|off <jugador>          - módulo 3: suscripción a alertas de un jugador
    /alertas                           - lista tus suscripciones activas
    /ayuda
"""
from __future__ import annotations

import logging

from sqlalchemy import select
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

from fantasy_assistant.config import config
from fantasy_assistant.db.database import get_session
from fantasy_assistant.db.models import PlayerRecord, TelegramSubscription
from fantasy_assistant.modules import lineup_optimizer, price_predictor

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)

# Preferencia de fuente por chat_id. TODO fase 2: persistir en BD en vez de
# memoria (se pierde al reiniciar el bot).
USER_SOURCE: dict[int, str] = {}


def _find_player(nombre_query: str, source: str) -> PlayerRecord | None:
    nombre_query = nombre_query.strip().lower()
    with get_session() as session:
        rows = session.execute(
            select(PlayerRecord).where(PlayerRecord.source == source)
        ).scalars().all()
        for row in rows:
            if nombre_query in row.nombre.lower():
                return row
    return None


async def ayuda(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "Comandos disponibles:\n"
        "/fuente biwenger|laligafantasy - elige la fuente de datos\n"
        "/prediccion <jugador> - predicción de precio\n"
        "/alineacion <presupuesto> [formación] - optimizador de alineación (ej. /alineacion 60000000 4-3-3)\n"
        "/alertas on|off <jugador> - suscribirte a las alertas de precio de un jugador\n"
        "/alertas - lista tus suscripciones activas\n"
        "/ayuda - esta ayuda"
    )


async def fuente(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        actual = USER_SOURCE.get(update.effective_chat.id, config.fantasy_source)
        await update.message.reply_text(f"Fuente actual: {actual}\nUso: /fuente biwenger|laligafantasy")
        return

    nueva_fuente = context.args[0].lower()
    if nueva_fuente not in ("biwenger", "laligafantasy"):
        await update.message.reply_text("Fuente inválida. Usa 'biwenger' o 'laligafantasy'.")
        return

    USER_SOURCE[update.effective_chat.id] = nueva_fuente
    await update.message.reply_text(f"Fuente configurada: {nueva_fuente}")


async def prediccion(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("Uso: /prediccion <jugador>")
        return

    nombre_query = " ".join(context.args)
    source = USER_SOURCE.get(update.effective_chat.id, config.fantasy_source)

    player = _find_player(nombre_query, source)
    if not player:
        await update.message.reply_text(f"No encontré ningún jugador que coincida con '{nombre_query}'.")
        return

    result = price_predictor.predict_player(player.id)
    await update.message.reply_text(
        f"{player.nombre} ({player.equipo}, {player.posicion})\n"
        f"Predicción: {result.prediccion}\n"
        f"Confianza: {result.confianza:.0%}"
    )


async def alineacion(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text(
            "Uso: /alineacion <presupuesto> [formación]\n"
            f"Formaciones: {', '.join(lineup_optimizer.FORMACIONES)}\n"
            "Ejemplo: /alineacion 60000000 4-3-3"
        )
        return

    try:
        presupuesto = int(context.args[0])
    except ValueError:
        await update.message.reply_text("El presupuesto debe ser un número entero (en euros).")
        return

    formacion = context.args[1] if len(context.args) > 1 else "4-3-3"
    source = USER_SOURCE.get(update.effective_chat.id, config.fantasy_source)

    try:
        resultado = lineup_optimizer.optimize_lineup(presupuesto=presupuesto, formacion=formacion, source=source)
    except lineup_optimizer.LineupError as e:
        await update.message.reply_text(str(e))
        return

    lineas = [f"Alineación {resultado.formacion} — {resultado.puntos_esperados:.1f} pts esperados"]
    for jugador in resultado.jugadores:
        lineas.append(f"{jugador.posicion} {jugador.nombre} ({jugador.equipo}) — {jugador.precio / 1_000_000:.2f} M€")
    lineas.append(f"\nPresupuesto usado: {resultado.presupuesto_usado / 1_000_000:.2f} M€ de {presupuesto / 1_000_000:.2f} M€")
    await update.message.reply_text("\n".join(lineas))


async def alertas(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = str(update.effective_chat.id)

    if not context.args:
        with get_session() as session:
            rows = session.execute(
                select(PlayerRecord.nombre)
                .join(TelegramSubscription, TelegramSubscription.player_id == PlayerRecord.id)
                .where(TelegramSubscription.chat_id == chat_id)
            ).scalars().all()
        if not rows:
            await update.message.reply_text(
                "No tienes ninguna alerta activa.\nUso: /alertas on|off <jugador>"
            )
        else:
            await update.message.reply_text("Suscrito a las alertas de:\n" + "\n".join(f"- {n}" for n in rows))
        return

    accion = context.args[0].lower()
    if accion not in ("on", "off") or len(context.args) < 2:
        await update.message.reply_text("Uso: /alertas on|off <jugador>")
        return

    nombre_query = " ".join(context.args[1:])
    source = USER_SOURCE.get(update.effective_chat.id, config.fantasy_source)
    player = _find_player(nombre_query, source)
    if not player:
        await update.message.reply_text(f"No encontré ningún jugador que coincida con '{nombre_query}'.")
        return

    with get_session() as session:
        existente = session.execute(
            select(TelegramSubscription).where(
                TelegramSubscription.chat_id == chat_id, TelegramSubscription.player_id == player.id
            )
        ).scalar_one_or_none()

        if accion == "on":
            if not existente:
                session.add(TelegramSubscription(chat_id=chat_id, player_id=player.id))
            mensaje = f"Te avisaré de cambios de precio de {player.nombre}."
        else:
            if existente:
                session.delete(existente)
            mensaje = f"Ya no recibirás alertas de {player.nombre}."

    await update.message.reply_text(mensaje)


def build_app() -> Application:
    if not config.telegram_bot_token:
        raise RuntimeError("TELEGRAM_BOT_TOKEN no está configurado en .env")

    app = Application.builder().token(config.telegram_bot_token).build()
    app.add_handler(CommandHandler("ayuda", ayuda))
    app.add_handler(CommandHandler("fuente", fuente))
    app.add_handler(CommandHandler("prediccion", prediccion))
    app.add_handler(CommandHandler("alineacion", alineacion))
    app.add_handler(CommandHandler("alertas", alertas))
    return app


def main() -> None:
    app = build_app()
    logger.info("Bot de Telegram arrancado")
    app.run_polling()


if __name__ == "__main__":
    main()
