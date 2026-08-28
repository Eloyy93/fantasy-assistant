import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'api_client.dart';

/// Tema oscuro con acento verde menta y tipografía Inter, inspirado en
/// apps de datos de fantasy football: fondo casi negro con un puntito de
/// azul, tarjetas con borde sutil en vez de sombra plana, jerarquía
/// tipográfica clara (no todo el mismo tamaño de letra gris).
const kMintAccent = Color(0xFF21E6A4);
const kBgColor = Color(0xFF0A0B0D);
const kSurfaceColor = Color(0xFF16181B);
const kSurfaceHighColor = Color(0xFF1D2023);
const kBorderColor = Color(0xFF262A2E);
const kTextSecondary = Color(0xFF9AA3A8);
const kTextTertiary = Color(0xFF666E73);

final fantasyTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: GoogleFonts.inter().fontFamily,
  textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
    headlineSmall: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
    bodyMedium: GoogleFonts.inter(fontSize: 14, color: kTextSecondary),
    labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6),
  ),
  colorScheme: ColorScheme.fromSeed(
    seedColor: kMintAccent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kMintAccent,
    surface: kSurfaceColor,
    surfaceContainerHighest: kSurfaceHighColor,
    onSurfaceVariant: kTextSecondary,
    outline: kBorderColor,
  ),
  scaffoldBackgroundColor: kBgColor,
  appBarTheme: AppBarTheme(
    backgroundColor: kBgColor,
    foregroundColor: Colors.white,
    centerTitle: false,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
  ),
  cardTheme: CardThemeData(
    color: kSurfaceColor,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: kBorderColor),
    ),
  ),
  dividerTheme: const DividerThemeData(color: kBorderColor, thickness: 1, space: 1),
  listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurfaceColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: kBorderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: kBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: kMintAccent, width: 1.5),
    ),
    labelStyle: const TextStyle(color: kTextSecondary),
    hintStyle: const TextStyle(color: kTextTertiary),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: kMintAccent,
      foregroundColor: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: kBorderColor),
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  ),
  dropdownMenuTheme: DropdownMenuThemeData(
    textStyle: GoogleFonts.inter(color: Colors.white),
    menuStyle: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(kSurfaceHighColor),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: kSurfaceHighColor,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: kBorderColor),
    ),
    textStyle: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
  ),
);

/// Color por posición: dorado=portero, azul=defensa, menta=medio, rojo=delantero.
Color colorForPosicion(String posicion) {
  switch (posicion) {
    case 'POR':
      return const Color(0xFFE8B23C);
    case 'DEF':
      return const Color(0xFF4C8CE8);
    case 'MED':
      return kMintAccent;
    case 'DEL':
      return const Color(0xFFE85D6B);
    default:
      return kTextSecondary;
  }
}

/// Chip de posición: fondo tintado translúcido + texto del color de la
/// posición, en vez de un círculo relleno — más fino, mismo lenguaje que
/// las apps de datos de fantasy (etiquetas discretas, no iconos grandes).
class PositionBadge extends StatelessWidget {
  final String posicion;
  final double size;

  const PositionBadge({super.key, required this.posicion, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final color = colorForPosicion(posicion);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        posicion,
        style: TextStyle(color: color, fontSize: size * 0.29, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      ),
    );
  }
}

/// Foto del jugador en un círculo, con el mismo fallback visual que
/// [PositionBadge] (fondo tintado + iniciales de la posición) mientras
/// carga o si la foto no existe — no toda foto resuelve (algunos jugadores
/// no tienen imagen en la fuente).
class PlayerAvatar extends StatelessWidget {
  final String fotoUrl;
  final String posicion;
  final double size;

  const PlayerAvatar({super.key, required this.fotoUrl, required this.posicion, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final color = colorForPosicion(posicion);
    if (fotoUrl.isEmpty) {
      return PositionBadge(posicion: posicion, size: size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Container(
        width: size,
        height: size,
        color: color.withValues(alpha: 0.16),
        child: Image.network(
          webSafePhotoUrl(fotoUrl),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, _, _) => PositionBadge(posicion: posicion, size: size),
          loadingBuilder: (context, child, progress) => progress == null ? child : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Una pequeña estadística en formato "etiqueta arriba, valor grande abajo",
/// usada para desglosar resultados (formación, puntos, presupuesto...) en
/// vez de meterlo todo en un párrafo de texto corrido.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const StatTile({super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: kTextTertiary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor ?? Colors.white),
        ),
      ],
    );
  }
}

/// Encabezado de sección: etiqueta pequeña en mayúsculas gris, para separar
/// bloques de contenido sin recurrir a títulos grandes constantes.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: kTextTertiary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
