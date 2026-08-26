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
| Módulo 2 — Optimizador de alineación | Funcionando (mochila por posición sobre todo el mercado) |
| Módulo 3 — Alertas | Funcionando (push vía FCM, cambio de precio >3% entre syncs) |
| API REST (`fantasy_assistant/api`) | Funcionando: `/players`, `/players/{id}/prediccion`, `/lineup`, `/devices` |
| Bot de Telegram | `/prediccion` y `/alineacion` funcionando end-to-end; `/alertas` responde "pendiente" (fase 3b: suscripción por jugador) |
| App Android (Flutter, `app/`) | Funcionando, apuntando al backend en producción |
| Despliegue backend | **En producción en Railway**, sincronizando datos reales cada 3h |
| Notificaciones push (FCM) | Funcionando, verificado extremo a extremo |

## App Android (Flutter)

Código en `app/`. Flutter SDK instalado en `C:\src\flutter` (añadido al PATH
de usuario). Comandos desde `app/`:

```bash
flutter pub get
flutter run              # con un emulador o móvil conectado
flutter build apk        # genera build/app/outputs/flutter-apk/app-release.apk
```

La URL del backend está en `app/lib/api_client.dart` (`kApiBaseUrl`), ya
apuntando al backend desplegado en Railway.

## Backend en producción (Railway)

Un único servicio (`fantasy-assistant`), construido desde el `Dockerfile` de
este repo. La API sincroniza datos ella misma al arrancar y cada 3h (ver
`fantasy_assistant/api/main.py`, `BackgroundScheduler`) — no hay un servicio
de sync aparte ni un Volume montado; la BD SQLite vive dentro del propio
contenedor (`/app/data`), así que **se resetea en cada redeploy** y se
vuelve a poblar sola en segundos.

Notas del despliegue, por si hay que tocarlo de nuevo:
- El puerto que usa uvicorn lo decide Railway vía la variable `$PORT` que
  inyecta él mismo (no hace falta fijarla a mano) — el dominio público debe
  apuntar a ese mismo puerto en **Settings → Networking**.
- El **Custom Start Command** del servicio debe estar vacío para que se use
  el `CMD` del `Dockerfile` (uvicorn). Si algún día se vuelve a poner un
  comando de sync ahí por error, la API deja de responder (502).

Para probar la imagen en local antes de desplegar (necesita Docker Desktop arrancado):

```bash
docker build -t fantasy-assistant-api .
docker run -p 8000:8000 -e FANTASY_SOURCE=biwenger fantasy-assistant-api
```

## Módulo 2 — Optimizador de alineación

Dado un presupuesto y una formación (`4-3-3`, `4-4-2`, `3-4-3`, `3-5-2`,
`5-3-2` o `5-4-1`), elige entre TODOS los jugadores del mercado la
combinación que maximiza la suma de puntos esperados (media de las últimas
3 jornadas de cada jugador) sin superar el presupuesto — un problema de
mochila por grupos (posición = grupo, hay que elegir exactamente N de cada
una), resuelto con programación dinámica en `modules/lineup_optimizer.py`.

# TODO fase 2b: usar la plantilla real del usuario (login + `get_user_team()`,
ya implementado en `BiwengerAdapter`) en vez de un presupuesto manual, para
no sugerir comprar jugadores que ya tiene.

## Arquitectura

Patrón adaptador: toda la app habla con la interfaz `FantasyDataSource`
(`fantasy_assistant/datasources/base.py`), nunca con Biwenger o LaLiga Fantasy
directamente. Cambiar de fuente es cuestión de cambiar `FANTASY_SOURCE` en `.env`.
