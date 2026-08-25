# Fantasy Assistant

Asistente para gestionar una plantilla de fútbol fantasy (LaLiga), con dos
fuentes de datos intercambiables: **Biwenger** y **LaLiga Fantasy** (fase 2).

Interfaz principal: **app Android (Flutter)** en `app/`, hablando contra la
API REST de este repo, con notificaciones push (Firebase Cloud Messaging)
pendientes de fase 3. El bot de Telegram se mantiene como interfaz de
pruebas rápida.

## Configuración

```bash
cp .env.example .env
```

Variables principales en `.env`:

- `FANTASY_SOURCE`: `biwenger` (disponible) o `laligafantasy` (fase 2, aún sin implementar).
- `DATABASE_URL`: por defecto SQLite local (`sqlite:///fantasy_assistant.db`).
- `TELEGRAM_BOT_TOKEN`: token del bot, créalo con [@BotFather](https://t.me/BotFather).
- `BIWENGER_EMAIL` / `BIWENGER_PASSWORD`: opcionales, solo necesarios para leer tu plantilla (`/alineacion`, fase 2).
- `PRICE_PREDICTOR_UP_THRESHOLD` / `PRICE_PREDICTOR_DOWN_THRESHOLD`: umbrales del predictor de precio (módulo 1).

## Instalación

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

## Uso

```bash
# Sincronizar datos a la BD local (una vez)
python -m fantasy_assistant.jobs.sync_data

# Sincronizar en bucle cada 3h (para alertas del módulo 3, fase 3)
python -m fantasy_assistant.jobs.sync_data --loop

# Arrancar todo (BD + sync inicial + bot de Telegram)
python -m fantasy_assistant.main

# API REST (para la futura app Android)
uvicorn fantasy_assistant.api.main:app --reload
# -> docs interactivas en http://127.0.0.1:8000/docs
```

## Estado actual

| Componente | Estado |
|---|---|
| `BiwengerAdapter` | Funcionando (datos públicos de jugadores, sin auth) |
| `LaLigaFantasyAdapter` | Stub, fase 2 (OAuth2 B2C) |
| Módulo 1 — Predictor de precio | Funcionando (reglas simples) |
| Módulo 2 — Optimizador de alineación | Stub, fase 2 |
| Módulo 3 — Alertas | Stub, fase 3 (push vía Firebase Cloud Messaging) |
| API REST (`fantasy_assistant/api`) | Funcionando: `/players`, `/players/{id}/prediccion`, `/devices` |
| Bot de Telegram | `/prediccion` funcionando end-to-end; `/alineacion` y `/alertas` responden "pendiente" |
| App Android (Flutter, `app/`) | Funcionando: buscador de jugadores + predicción, probado en emulador contra la API real |
| Despliegue backend | `Dockerfile` + `railway.json` listos, sin desplegar (requiere cuenta Railway/Fly.io) |
| Notificaciones push (FCM) | Pendiente fase 3, junto con `modules/alerts.py` |

## App Android (Flutter)

Código en `app/`. Flutter SDK instalado en `C:\src\flutter` (añadido al PATH
de usuario). Comandos desde `app/`:

```bash
flutter pub get
flutter run              # con un emulador o móvil conectado
flutter build apk        # genera build/app/outputs/flutter-apk/app-release.apk
```

La URL del backend está en `app/lib/api_client.dart` (`kApiBaseUrl`):
- `http://10.0.2.2:8000` funciona tal cual contra un backend local desde el
  **emulador** Android (ya probado).
- Para un móvil físico o el backend ya desplegado, cambia esa constante por
  la IP LAN de tu PC o por la URL pública de Railway/Fly.io.

## Desplegar el backend (Railway)

1. `pip install -r requirements.txt` ya lo cubre todo; no hace falta nada más en el repo.
2. Sube el repo a GitHub, conéctalo en [railway.app](https://railway.app) — detecta `railway.json` + `Dockerfile` solo.
3. Configura en Railway las variables de entorno de `.env.example` (como mínimo `FANTASY_SOURCE`; `DATABASE_URL` puedes dejarlo, el `Dockerfile` ya monta un volumen en `/data`).
4. El job de sincronización (`python -m fantasy_assistant.jobs.sync_data --loop`) debe correr como **servicio aparte** en Railway (mismo repo, mismo Dockerfile, pero sobrescribiendo el `CMD` por ese comando) — la API y el sync no deben compartir proceso.

Para probar la imagen en local antes de desplegar (necesita Docker Desktop arrancado):

```bash
docker build -t fantasy-assistant-api .
docker run -p 8000:8000 -e FANTASY_SOURCE=biwenger fantasy-assistant-api
```

## Arquitectura

Patrón adaptador: toda la app habla con la interfaz `FantasyDataSource`
(`fantasy_assistant/datasources/base.py`), nunca con Biwenger o LaLiga Fantasy
directamente. Cambiar de fuente es cuestión de cambiar `FANTASY_SOURCE` en `.env`.
