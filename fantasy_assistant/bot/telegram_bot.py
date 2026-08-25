"""Bot de Telegram — interfaz de usuario de Fantasy Assistant.

Comandos v1:
    /fuente biwenger | laligafantasy   - elige la fuente de datos (por usuario)
    /prediccion <jugador>              - módulo 1 (predictor de precio)
    /alineacion                        - módulo 2 (TODO fase 2)
    /alertas on|off <jugador>          - módulo 3 (TODO fase 3)
    /ayuda
"""
from __future__ import annotations

import logging

from sqlalchemy import select
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

from fantasy_assistant.config import config
from fantasy_assistant.db.database import get_session
from fantasy_assistant.db.models import PlayerRecord
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
        "/alineacion - optimizador de alineación (fase 2)\n"
        "/alertas on|off <jugador> - alertas (fase 3)\n"
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
    try:
        lineup_optimizer.optimize_lineup(user_id=str(update.effective_chat.id), presupuesto=0, formacion="4-3-3")
    except NotImplementedError:
        await update.message.reply_text("El optimizador de alineación llega en la fase 2. Aún no está disponible.")


async def alertas(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("Las alertas llegan en la fase 3. Aún no están disponibles.")


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
