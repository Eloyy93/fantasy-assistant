// ⚠️ ARCHIVO GENERADO AUTOMÁTICAMENTE — placeholder temporal.
//
// El login con Google necesita que Firebase esté configurado también para
// Web (hasta ahora solo lo estaba para Android, vía google-services.json).
// Para generar los valores reales de este archivo:
//
//   1. npm install -g firebase-tools   (o usa `npx firebase-tools`)
//   2. firebase login
//   3. dart pub global activate flutterfire_cli
//   4. flutterfire configure --project=<tu-proyecto-firebase>
//      (ejecutar dentro de app/, elige Android + Web cuando pregunte)
//
// Eso SOBRESCRIBE este archivo con las credenciales reales del proyecto.
// Con los valores de abajo (falsos) la app compila pero el login no
// funcionará — es solo para que el resto del código tenga algo válido
// contra lo que compilar mientras tanto.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('DefaultFirebaseOptions no soporta esta plataforma.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBN7rf_xE-SayZaVd2bOT8dYUUjYfOoUbo',
    appId: '1:191835506057:web:6d603d04c35ccce9bccd58',
    messagingSenderId: '191835506057',
    projectId: 'fantasy-assistant-a69ba',
    authDomain: 'fantasy-assistant-a69ba.firebaseapp.com',
    storageBucket: 'fantasy-assistant-a69ba.firebasestorage.app',
    measurementId: 'G-TKVB1JFSB4',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDTyalfXemyFd4oudvhu-zMEzvoUXfkYPc',
    appId: '1:191835506057:android:c20990f021fa4bbcbccd58',
    messagingSenderId: '191835506057',
    projectId: 'fantasy-assistant-a69ba',
    storageBucket: 'fantasy-assistant-a69ba.firebasestorage.app',
  );
}
