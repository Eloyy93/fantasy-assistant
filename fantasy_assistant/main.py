"""Punto de entrada: inicializa la BD, sincroniza datos y arranca el bot."""
from __future__ import annotations

from fantasy_assistant.bot.telegram_bot import main as run_bot
from fantasy_assistant.db.database import init_db
from fantasy_assistant.jobs.sync_data import sync_once


def main() -> None:
    init_db()
    sync_once()
    run_bot()


if __name__ == "__main__":
    main()
