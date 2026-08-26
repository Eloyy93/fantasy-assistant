import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'fantasy_assistant_device_id';

String _randomId() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Identificador local del dispositivo para "Mi plantilla" — independiente
/// del token FCM, para que gestionar la plantilla no requiera tener las
/// notificaciones push activadas. Se genera una vez y se guarda en disco.
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_prefsKey);
  if (existing != null) return existing;

  final nuevo = _randomId();
  await prefs.setString(_prefsKey, nuevo);
  return nuevo;
}
