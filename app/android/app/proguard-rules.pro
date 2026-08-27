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
