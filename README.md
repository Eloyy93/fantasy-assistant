# Fantasy Assistant

Asistente para gestionar una plantilla de fútbol fantasy (LaLiga), con dos
fuentes de datos intercambiables: **Biwenger** y **LaLiga Fantasy**.

Interfaz **única**: app Android (Flutter) en `app/`, hablando contra la API
REST de este repo, con notificaciones push (Firebase Cloud Messaging) por
jugador suscrito. No hay bot de Telegram ni ninguna otra interfaz — todo
pasa por la app.

## Configuración

```bash
cp .env.example .env
```

Variables principales en `.env`:

- `FANTASY_SOURCE`: `biwenger` o `laligafantasy` (ambas leen jugadores reales; el login de usuario en LaLiga Fantasy sigue sin implementar, ver más abajo).
- `DATABASE_URL`: por defecto SQLite local (`sqlite:///fantasy_assistant.db`).
- `BIWENGER_EMAIL` / `BIWENGER_PASSWORD`: opcionales, solo necesarios para leer tu plantilla (optimizador, fase 2b).
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

# Sincronizar en bucle cada 3h (para las alertas del módulo 3)
python -m fantasy_assistant.jobs.sync_data --loop

# Arrancar la API REST (única interfaz)
python -m fantasy_assistant.main
# equivalente a:
uvicorn fantasy_assistant.api.main:app --reload
# -> docs interactivas en http://127.0.0.1:8000/docs
```

## Estado actual

| Componente | Estado |
|---|---|
| `BiwengerAdapter` | Funcionando (datos públicos de jugadores, sin auth) |
| `LaLigaFantasyAdapter` | Jugadores + histórico de precio funcionando (endpoints públicos); login de usuario pendiente a propósito (fase 2b, ver abajo) |
| Módulo 1 — Predictor de precio | Funcionando (reglas simples) |
| Módulo 2 — Optimizador de alineación | Funcionando (mochila por posición sobre todo el mercado) |
| Módulo 3 — Alertas | Funcionando: push por jugador, solo a los dispositivos suscritos a ese jugador concreto |
| API REST (`fantasy_assistant/api`) | Funcionando: `/players`, `/players/{id}/prediccion`, `/lineup`, `/devices`, `/subscriptions` |
| App Android (Flutter, `app/`) | Funcionando, apuntando al backend en producción — única interfaz de usuario |
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

## LaLiga Fantasy — qué falta y por qué

`get_all_players()` y `get_player_price_history()` funcionan de verdad
contra los endpoints públicos de `api-fantasy.llt-services.com` (sin
credenciales). El parseo está verificado contra el schema real documentado
por terceros que ya la habían reverse-engineered, pero no pude probar la
llamada HTTP en vivo — el backend de LALIGA devolvía 502 en el momento de
escribir esto (caída de su lado). Antes de sincronizar con esta fuente por
primera vez, comprueba que funciona:

```bash
FANTASY_SOURCE=laligafantasy python -m fantasy_assistant.jobs.sync_data
```

`login()` / `get_user_team()` siguen sin implementar **a propósito**, no
por falta de tiempo: requieren un flujo ROPC completo contra un tenant B2C
de Azure AD (credenciales de usuario reales, no una API key), y una de las
fuentes consultadas para documentar esto había bloqueado explícitamente esa
parte de su propio proyecto "hasta autorización escrita de LALIGA". Antes
de implementarlo, vale la pena decidir conscientemente si seguir adelante.

No se encontró tampoco ningún endpoint público con el nombre real de cada
equipo (solo `teamId`) ni con los puntos por jornada (solo el acumulado de
temporada) — quedan documentados como TODO en el propio adaptador.

## Arquitectura

Patrón adaptador: toda la app habla con la interfaz `FantasyDataSource`
(`fantasy_assistant/datasources/base.py`), nunca con Biwenger o LaLiga Fantasy
directamente. Cambiar de fuente es cuestión de cambiar `FANTASY_SOURCE` en `.env`.
