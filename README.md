# Fantasy Assistant (app: Master Fantasy)

Asistente para gestionar una plantilla de fútbol fantasy (LaLiga), con dos
fuentes de datos intercambiables: **Biwenger** y **LaLiga Fantasy**. El
backend/repo sigue llamándose Fantasy Assistant; la app Android que ve el
usuario se llama **Master Fantasy** (nombre + icono en `app/`).

Interfaz **única**: app Android (Flutter) en `app/`, hablando contra la API
REST de este repo, con notificaciones push (Firebase Cloud Messaging) por
jugador suscrito. No hay bot de Telegram ni ninguna otra interfaz — todo
pasa por la app.

## Configuración

```bash
cp .env.example .env
```

Variables principales en `.env`:

- `FANTASY_SOURCE`: fuente por defecto para uso desde CLI (`python -m fantasy_assistant.jobs.sync_data`) — en producción la API sincroniza **ambas** fuentes siempre, independientemente de esta variable. El usuario elige cuál ver desde la app (selector Biwenger/LaLiga Fantasy).
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
| `BiwengerAdapter` | Funcionando: jugadores + histórico de precio real (365 días, ver abajo), sin auth |
| `LaLigaFantasyAdapter` | Jugadores + histórico de precio + puntos esperados funcionando de verdad (scraping de futbolfantasy.com, ver abajo); login de usuario pendiente a propósito (fase 2b) |
| Módulo 1 — Predictor de precio | Funcionando (reglas simples) |
| Módulo 2 — Optimizador de alineación | Funcionando (mochila por posición sobre todo el mercado), maximiza puntos esperados dentro del presupuesto para **ambas** fuentes (Biwenger y LaLiga Fantasy, selector `source` en `/lineup`) |
| Módulo 3 — Alertas | Funcionando: push por jugador, solo a los dispositivos suscritos a ese jugador concreto |
| Mi plantilla | Funcionando: sistema estilo Futbin — elige formación, toca un hueco vacío y la app recomienda los mejores jugadores de esa posición (por puntos de temporada) + buscador para añadir a cualquier otro; independiente de las notificaciones push (device_id propio) |
| API REST (`fantasy_assistant/api`) | Funcionando: `/players` (búsqueda insensible a acentos), `/players/{id}/prediccion`, `/players/{id}/historial`, `/compare`, `/lineup`, `/devices`, `/subscriptions`, `/team`, `/team/formacion`, `/team/recomendados` |
| Comparador de jugadores | Funcionando: `/compare?a=&b=` — puntos recientes/temporada, variación de precio y próximo rival de dos jugadores lado a lado |
| Análisis de calendario/rival | Funcionando (rico en Biwenger, básico en LaLiga Fantasy — ver abajo): ajusta la confianza del predictor de precio (módulo 1) según qué tan difícil es el próximo rival, y se puede ver el motivo en la ficha del jugador y en el comparador |
| Monetización | Anuncios (banner) y suscripción "sin anuncios" con código listo, ver `app/lib/ads_service.dart` y `app/lib/purchase_service.dart` — **con IDs de PRUEBA** hasta crear cuenta de AdMob y publicar en Play Store (ver sección abajo) |
| App Android (Flutter, `app/`) | Funcionando, apuntando al backend en producción — única interfaz de usuario, con selector de fuente (Biwenger/LaLiga Fantasy) |
| Despliegue backend | **En producción en Railway**, sincronizando Biwenger y LaLiga Fantasy en paralelo cada 3h (cada una independiente: si una falla no afecta a la otra) |
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

## Módulo 1 — Análisis de calendario/rival

`FantasyDataSource.get_rival_analysis(player_id)` da el próximo rival del
jugador y, cuando la fuente lo permite, qué tan duro es ese rival y cómo le
ha ido a este jugador contra él en el pasado:

- **Biwenger**: rico. Un único endpoint de ficha de jugador
  (`/players/la-liga/{id}?history=1&fields=id,team,scoreStats`) da el
  próximo partido con una `difficulty.rating` (0=flojo..100=top, calculada
  por el propio Biwenger) **y** `scoreStats`, el rendimiento histórico de
  ese jugador concreto contra cada rival concreto (puntos y partidos
  jugados en su contra, acumulado de todas las temporadas) — sin peticiones
  extra más allá de la que ya hace `get_player_price_history()`.
- **LaLiga Fantasy**: básico. No hay forma pública de saber la dificultad
  del rival ni el histórico jugador-contra-equipo — solo el nombre del
  próximo rival, ya disponible en el scraping que se hace cada sync para la
  media de puntos.

El predictor de precio (`price_predictor.predict_for_points`) usa la
dificultad del rival (cuando la hay) para subir o bajar la **confianza** de
su predicción — nunca para cambiar si dice "sube"/"baja"/"estable", que
sigue basándose solo en los puntos reales. Un rival flojo que refuerza una
tendencia de subida da más seguridad; un rival duro que la contradice,
menos. Se puede ver el motivo tanto en la ficha del jugador
(`/players/{id}/prediccion`) como en el comparador (`/compare`).

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

## Biwenger — histórico de precio

El endpoint público de ficha de jugador (`/players/la-liga/{id}`) no incluye
histórico de precio por defecto, pero si se piden explícitamente los
`fields=id,prices` sí lo devuelve — 365 días, uno por día. Es una petición
extra por jugador (no viene en el listado general).

Biwenger rate-limita esta ruta con bastante agresividad — verificado en
producción: ni siquiera 1s de margen entre peticiones bastó para evitar un
429 a los pocos jugadores. `get_player_price_history()` no reintenta un 429
con backoff (eso fue lo que convirtió una sincronización de minutos en una
de más de una hora, con la mayoría de jugadores fallando igual): en cuanto
llega el primer 429, se rinde para el resto de esa sincronización entera.
`sync_data.sync_once()` mezcla el orden de los jugadores en cada
sincronización para que, con el tiempo (una cada 3h), todos acaben
consiguiendo histórico aunque ninguna sincronización individual llegue a
completarlos todos.

## LaLiga Fantasy — de dónde salen los datos y por qué

La API oficial no documentada (`api-fantasy.llt-services.com`) lleva caída
desde que se investigó por primera vez este adaptador — 502 de Azure
Application Gateway, confirmado con `curl` y con navegador real, con y sin
cabeceras de la app oficial. Es una caída de infraestructura real de
LALIGA, no un bloqueo selectivo: afecta a cualquiera, headers aparte.

En vez de esperar sin plazo a que lo arreglen, `get_all_players()` y
`get_player_price_history()` sacan los datos de **futbolfantasy.com**: su
tabla de mercado viene enteramente renderizada en el HTML que sirve el
servidor (sin JavaScript de por medio), y cada fila `<tr>` lleva el id,
nombre, posición, precio actual **y precios de hace 1/2/3/7/14/30 días**
como atributos `data-*`. Una sola petición cada 3h nos da los ~670
jugadores y hasta 6 puntos de histórico de precio de golpe — verificado
con datos reales en producción. `robots.txt` de futbolfantasy.com es
permisivo (`Disallow:` vacío); a una petición cada 3h es tráfico mínimo.

Si LALIGA arregla su API oficial en algún momento, sería más correcto
volver a ella (más estable que depender del HTML de un tercero, que se
rompe si cambian las clases de su tabla) — queda como TODO en el propio
adaptador.

`login()` / `get_user_team()` siguen sin implementar **a propósito**, no
por falta de tiempo: requieren un flujo ROPC completo contra un tenant B2C
de Azure AD (credenciales de usuario reales, no una API key), y una de las
fuentes consultadas para documentar esto había bloqueado explícitamente esa
parte de su propio proyecto "hasta autorización escrita de LALIGA". Antes
de implementarlo, vale la pena decidir conscientemente si seguir adelante.

`get_player_points_history()` trae el desglose **real** jornada a jornada:
`/analytics/laliga-fantasy/puntos` abre, por jugador, un modal
(`/analytics/stats/detalle/{id}/{temporada}`) con una fila por partido
jugado y su puntuación exacta en modo "laliga-fantasy". Es una petición
extra por jugador (no viene en el listado general), así que la
sincronización tarda unos 5-6 minutos más por esto — con un margen de 0.4s
entre peticiones para no saltar el rate-limiting del sitio (confirmado:
sin margen, corta la conexión a partir de la petición ~40). Con eso el
optimizador (módulo 2) recibe puntos reales de LaLiga Fantasy, no
sintéticos, igual que ya tenía con Biwenger.

## Monetización — anuncios y suscripción "sin anuncios"

Código listo en `app/lib/ads_service.dart` (banner, `google_mobile_ads`) y
`app/lib/purchase_service.dart` (suscripción mensual, `in_app_purchase`),
pero con **IDs de prueba oficiales de Google** — no sirven anuncios reales
ni cobran de verdad todavía. Pasos pendientes, en orden, para que esto
genere ingresos reales:

1. **Cuenta de Google Play Developer** (25$ pago único) y publicar la app
   en Play Store — obligatorio para que la suscripción funcione, ya que
   Play Billing (la única vía nativa de pago recurrente en Android) exige
   distribución por Play Store.
2. **Cuenta de AdMob**, registrar la app ahí, crear un bloque de anuncios
   tipo "Banner". Sustituir:
   - El App ID de prueba en `app/android/app/src/main/AndroidManifest.xml`
     (`com.google.android.gms.ads.APPLICATION_ID`) por el real.
   - `_testBannerAdUnitId` en `app/lib/ads_service.dart` por el Ad Unit ID
     real del bloque banner.
3. En **Play Console → Monetización → Productos → Suscripciones**, crear
   un producto con el ID exacto `master_fantasy_no_ads_monthly` (constante
   `noAdsProductId` en `app/lib/purchase_service.dart`) y el precio mensual
   que se quiera cobrar.

Hasta que se complete el paso 1, la app **no puede publicarse tal cual**
con AdMob en modo prueba: mostrar anuncios de prueba a usuarios reales
puede hacer que Google suspenda la cuenta de AdMob por tráfico inválido —
el paso 2 debe ir antes de repartir el APK más ampliamente.

Nota sobre seguridad de la suscripción: el estado "sin anuncios" se guarda
localmente en el dispositivo al completarse una compra que Google Play ya
validó en su propio flujo — suficiente para el tamaño actual del proyecto,
pero no a prueba de manipulación (un dispositivo rooteado podría falsificar
ese flag local). Blindarlo del todo requeriría validar el recibo contra la
Google Play Developer API desde este mismo backend — no implementado,
razonable de añadir si la app crece.

## Arquitectura

Patrón adaptador: toda la app habla con la interfaz `FantasyDataSource`
(`fantasy_assistant/datasources/base.py`), nunca con Biwenger o LaLiga Fantasy
directamente. Cambiar de fuente es cuestión de cambiar `FANTASY_SOURCE` en `.env`.
