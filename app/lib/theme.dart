import 'package:flutter/material.dart';

/// Tema de la app: verde césped, acorde a una app de fantasy football en
/// vez del morado/naranja genérico de Material por defecto.
const _pitchGreen = Color(0xFF1E7D3C);

final fantasyTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _pitchGreen,
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: const Color(0xFFF5F7F3),
  appBarTheme: const AppBarTheme(
    backgroundColor: _pitchGreen,
    foregroundColor: Colors.white,
    centerTitle: false,
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _pitchGreen : null,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : null,
      ),
    ),
  ),
);

/// Color por posición, usado en las insignias de jugador (buscador, campo,
/// pantalla de predicción).
Color colorForPosicion(String posicion) {
  switch (posicion) {
    case 'POR':
      return const Color(0xFFE8A63C); // dorado, típico de portero
    case 'DEF':
      return const Color(0xFF3B6FD4); // azul
    case 'MED':
      return const Color(0xFF2E9E5B); // verde
    case 'DEL':
      return const Color(0xFFD64545); // rojo
    default:
      return Colors.grey;
  }
}
