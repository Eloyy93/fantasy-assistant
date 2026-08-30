FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY fantasy_assistant ./fantasy_assistant

# Ruta segura por defecto: funciona sin que hayas montado un Volume de
# Railway todavía. Cuando montes uno en /data, sobrescribe DATABASE_URL
# en las variables de entorno del servicio para persistir la BD ahí.
ENV DATABASE_URL=sqlite:////app/data/fantasy_assistant.db
RUN mkdir -p /app/data

EXPOSE 8000

# Railway asigna el puerto público vía $PORT; si no está definida (ej. en
# local con `docker run`), cae a 8000.
#
# El job de sincronización (jobs/sync_data.py --loop) corre en segundo
# plano en el MISMO contenedor, junto a la API — sin él, la base de
# datos de jugadores se queda vacía o con lo que se haya sembrado a mano
# (ver DATABASE_URL arriba: SQLite sin volumen persistente, así que
# además se resetea en cada despliegue). Sincroniza nada más arrancar y
# luego cada 3h, para ambas fuentes (Biwenger y LaLiga Fantasy).
CMD ["sh", "-c", "python -m fantasy_assistant.jobs.sync_data --loop & uvicorn fantasy_assistant.api.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
