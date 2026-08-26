"""Envío de alertas por Telegram a los chats suscritos a un jugador.

Se llama desde jobs/sync_data.py, que corre en un hilo de fondo (no en el
event loop async del propio bot), así que aquí se abre y cierra un event
loop propio con asyncio.run() para cada tanda de envíos.
"""
from __future__ import annotations

import asyncio
import logging

from fantasy_assistant.config import config
from fantasy_assistant.modules.alerts import Alert

logger = logging.getLogger(__name__)


def send_telegram_alert(alert: Alert, chat_ids: list[str]) -> None:
    if not config.telegram_bot_token or not chat_ids:
        return

    from telegram import Bot
    from telegram.error import TelegramError

    async def _enviar_todos() -> None:
        bot = Bot(token=config.telegram_bot_token)
        for chat_id in chat_ids:
            try:
                await bot.send_message(chat_id=chat_id, text=f"⚠️ {alert.mensaje}")
            except TelegramError:
                logger.exception("Fallo enviando alerta de Telegram a chat_id=%s", chat_id)

    asyncio.run(_enviar_todos())
