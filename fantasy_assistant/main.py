"""Punto de entrada local: arranca la API REST (única interfaz de la app)."""
from __future__ import annotations

import uvicorn


def main() -> None:
    uvicorn.run("fantasy_assistant.api.main:app", host="0.0.0.0", port=8000)


if __name__ == "__main__":
    main()
