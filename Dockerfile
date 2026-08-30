FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY fantasy_assistant ./fantasy_assistant
COPY alembic ./alembic
COPY alembic.ini .

EXPOSE 8000

# DATABASE_URL es obligatoria (Postgres — Neon en producción, ver
# variables de entorno del servicio en Railway). Ya no hay valor SQLite
# por defecto: esa base no era persistente y se reseteaba en cada
# despliegue, perdiendo el mercado de jugadores y la plantilla de todo
# el mundo.
#
# Railway asigna el puerto público vía $PORT; si no está definida (ej. en
# local con `docker run`), cae a 8000.
#
# `alembic upgrade head` corre antes de arrancar la API, para que el
# esquema de la BD esté al día en cada despliegue sin pasos manuales.
#
# La sincronización del mercado corre DENTRO del propio proceso de la
# API (ver el BackgroundScheduler en api/main.py) — no como un segundo
# proceso aparte. Lanzarla también aquí como proceso de shell separado
# hacía que ambas fuentes escribieran a la vez en la misma BD, lo que
# producía bloqueos silenciosos con SQLite (con Postgres ya no aplica,
# pero se mantiene un único proceso por simplicidad).
CMD ["sh", "-c", "alembic upgrade head && uvicorn fantasy_assistant.api.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
