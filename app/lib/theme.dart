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

/// Texto corto en español para cada valor de `estado` que da la fuente
/// (hoy: Biwenger directamente, y LaLiga Fantasy por contagio desde
/// Biwenger — ver `_propagar_estado_entre_fuentes` en sync_data.py, ya que
/// el estado físico de un jugador real es el mismo sea cual sea la fuente
/// de precios/puntos). "unknown" se trata como disponible: es el valor que
/// da Biwenger para jugadores sin ninguna incidencia registrada.
String etiquetaEstadoJugador(String estado) {
  switch (estado) {
    case 'injured':
      return 'Lesionado';
    case 'doubt':
      return 'Duda';
    case 'sanctioned':
      return 'Sancionado';
    case 'discarded':
      return 'Descartado';
    default:
      return 'Disponible';
  }
}

/// true si el estado es una incidencia real (no "disponible") — para los
/// sitios donde solo interesa avisar cuando hay algo que contar (ej. la
/// fila "Estado" del comparador, que antes se ocultaba entera si ninguno
/// de los dos jugadores tenía incidencia).
bool tieneIncidenciaFisica(String estado) => estado == 'injured' || estado == 'doubt' || estado == 'sanctioned' || estado == 'discarded';

Color colorForEstadoJugador(String estado) {
  switch (estado) {
    case 'injured':
      return const Color(0xFFEF5350);
    case 'doubt':
      return const Color(0xFFFFA726);
    case 'sanctioned':
      return const Color(0xFFAB47BC);
    case 'discarded':
      return kTextTertiary;
    default:
      return kMintAccent;
  }
}

IconData iconoEstadoJugador(String estado) {
  switch (estado) {
    case 'injured':
      return Icons.local_hospital_rounded;
    case 'doubt':
      return Icons.help_rounded;
    case 'sanctioned':
      return Icons.block_rounded;
    case 'discarded':
      return Icons.remove_circle_rounded;
    default:
      return Icons.check_circle_rounded;
  }
}

/// Icono compacto de disponibilidad (lesionado/duda/sancionado/descartado/
/// disponible) para poner junto al nombre en listas — mantener pulsado (o
/// pasar el ratón, en escritorio) enseña el motivo y retorno estimado si
/// la fuente lo da. Pensado para caber en una fila sin empujar el resto
/// del contenido, a diferencia de [PlayerStatusBadge].
class PlayerStatusIcon extends StatelessWidget {
  final String estado;
  final String? estadoInfo;
  final double size;
  // Local/visitante del próximo partido — null significa "aún no se ha
  // pedido/no está disponible", que simplemente no dibuja el segundo
  // icono en vez de mostrar un hueco o un error.
  final bool? esLocal;

  const PlayerStatusIcon({super.key, required this.estado, this.estadoInfo, this.size = 16, this.esLocal});

  @override
  Widget build(BuildContext context) {
    final titulo = etiquetaEstadoJugador(estado);
    final info = estadoInfo?.trim();
    final mensaje = (info != null && info.isNotEmpty) ? '$titulo — $info' : titulo;
    final iconoEstado = Tooltip(
      message: mensaje,
      triggerMode: TooltipTriggerMode.tap,
      child: Icon(iconoEstadoJugador(estado), color: colorForEstadoJugador(estado), size: size),
    );
    if (esLocal == null) return iconoEstado;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconoEstado,
        SizedBox(width: size * 0.25),
        Tooltip(
          message: esLocal! ? 'Juega en casa' : 'Juega fuera',
          triggerMode: TooltipTriggerMode.tap,
          child: Icon(
            esLocal! ? Icons.home_rounded : Icons.flight_takeoff_rounded,
            color: esLocal! ? kMintAccent : kTextTertiary,
            size: size,
          ),
        ),
      ],
    );
  }
}

/// Pastilla ("Lesionado", "Duda", "Disponible"...) con icono, para la
/// ficha de detalle del jugador donde sí hay espacio de sobra — en listas
/// compactas usa [PlayerStatusIcon]. Para el motivo y retorno estimado
/// (texto libre de la fuente) usa [PlayerStatusInfo] justo debajo.
class PlayerStatusBadge extends StatelessWidget {
  final String estado;
  final bool? esLocal;

  const PlayerStatusBadge({super.key, required this.estado, this.esLocal});

  @override
  Widget build(BuildContext context) {
    final color = colorForEstadoJugador(estado);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconoEstadoJugador(estado), color: color, size: 13),
              const SizedBox(width: 4),
              Text(
                etiquetaEstadoJugador(estado),
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.1),
              ),
            ],
          ),
        ),
        if (esLocal != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (esLocal! ? kMintAccent : kTextTertiary).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (esLocal! ? kMintAccent : kTextTertiary).withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  esLocal! ? Icons.home_rounded : Icons.flight_takeoff_rounded,
                  color: esLocal! ? kMintAccent : kTextTertiary,
                  size: 13,
                ),
                const SizedBox(width: 4),
                Text(
                  esLocal! ? 'Casa' : 'Fuera',
                  style: TextStyle(
                    color: esLocal! ? kMintAccent : kTextTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Motivo/retorno estimado que da la fuente (ej. "Lesión muscular. Retorno
/// estimado: Mediados de Septiembre.") — solo se muestra si hay
/// [estadoInfo], y solo tiene sentido en pantallas con espacio de sobra
/// (ficha de detalle), no en las listas compactas donde va [PlayerStatusBadge].
class PlayerStatusInfo extends StatelessWidget {
  final String estado;
  final String? estadoInfo;

  const PlayerStatusInfo({super.key, required this.estado, required this.estadoInfo});

  @override
  Widget build(BuildContext context) {
    final info = estadoInfo?.trim();
    if (info == null || info.isEmpty) return const SizedBox.shrink();
    final color = colorForEstadoJugador(estado);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(info, style: TextStyle(color: color, fontSize: 13, height: 1.3))),
        ],
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
