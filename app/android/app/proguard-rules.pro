# Flutter habilita R8 (minificación) por defecto en release, incluso sin
# configurarlo explícitamente. Sin estas reglas, R8 rompe librerías que usan
# reflexión — verificado con un crash real en release (no en debug):
# "Failed to create an instance of androidx.work.impl.WorkDatabase", causado
# por in_app_purchase_android (usa WorkManager/Room para el flujo de
# compras pendientes) al perder por reflexión sus clases generadas.

# WorkManager y Room generan código en tiempo de compilación e instancian
# clases por reflexión — no se pueden ofuscar/eliminar.
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# google_mobile_ads y in_app_purchase también usan reflexión/serialización
# internamente — evita que R8 elimine sus modelos por no verlos referenciados
# directamente desde el código Dart/Kotlin de la app.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.android.billingclient.** { *; }
-dontwarn com.google.android.gms.ads.**

# google_mlkit_text_recognition referencia en su código los reconocedores
# de chino/devanagari/japonés/coreano aunque solo usamos el de script
# latino (ver lineup_scan_io.dart) — sin sus dependencias añadidas, R8 no
# encuentra esas clases y rompe el build en vez de simplemente omitirlas.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Las clases internas de mlkit_vision_common (com.google.android.gms.internal.
# mlkit_vision_common.zz*) se construyen por reflexión — sin -keep, R8 las
# ofusca/reordena y el proceso de reconocimiento crashea en release (nunca en
# debug) con NullPointerException al llamar a getClass() sobre un objeto que
# debería haberse creado por esa vía. Crash real reproducido en producción.
#
# Un primer intento con -keep solo sobre vision.text/vision.common causó un
# crash NUEVO y peor: la app se cerraba al abrir, siempre, no solo al usar
# OCR — porque MlKitInitProvider (un ContentProvider que arranca con la app,
# antes de que se pinte nada) inicializa por reflexión TODOS los componentes
# de visión registrados, y uno de sus dependencias intermedias quedaba
# ofuscada igualmente ("Unsatisfied dependency ... np", visto con adb logcat
# en dispositivo real). La única forma fiable de que R8 no rompa esta cadena
# de reflexión es no tocar NINGUNA clase de com.google.mlkit ni de sus
# paquetes internos de gms, en vez de intentar adivinar cada símbolo.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.odml.image.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.odml.**
