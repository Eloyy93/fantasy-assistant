import 'package:flutter/material.dart';

/// Tema oscuro con acento verde menta, inspirado en apps de datos de
/// fantasy football (analiticafantasy.com): fondo casi negro, tarjetas gris
/// oscuro, números grandes en blanco, verde menta para lo positivo.
const kMintAccent = Color(0xFF1FE6A6);
const _bgColor = Color(0xFF0B0D0C);
const _cardColor = Color(0xFF171A19);

final fantasyTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kMintAccent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kMintAccent,
    surface: _cardColor,
    surfaceContainerHighest: _cardColor,
  ),
  scaffoldBackgroundColor: _bgColor,
  appBarTheme: const AppBarTheme(
    backgroundColor: _bgColor,
    foregroundColor: Colors.white,
    centerTitle: false,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  cardTheme: CardThemeData(
    color: _cardColor,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _cardColor,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? kMintAccent : _cardColor,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.black : Colors.white70,
      ),
      side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFF2A2E2C))),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(backgroundColor: kMintAccent, foregroundColor: Colors.black),
  ),
);

/// Color por posición, usado en las insignias de jugador (buscador, campo,
/// pantalla de predicción). Mismos tonos vivos, pensados para leerse bien
/// sobre fondo oscuro.
Color colorForPosicion(String posicion) {
  switch (posicion) {
    case 'POR':
      return const Color(0xFFE8A63C); // dorado, típico de portero
    case 'DEF':
      return const Color(0xFF4C82E8); // azul
    case 'MED':
      return kMintAccent;
    case 'DEL':
      return const Color(0xFFE85D5D); // rojo
    default:
      return Colors.grey;
  }
}
