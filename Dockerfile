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
CMD ["sh", "-c", "uvicorn fantasy_assistant.api.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
