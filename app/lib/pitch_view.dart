import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';

/// Dibuja las líneas de un campo de fútbol (banda, círculo central, áreas)
/// sobre un fondo verde, en orientación vertical (portería abajo).
class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linea = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final borde = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    canvas.drawRect(borde, linea);

    // Línea de medio campo.
    final mitadY = size.height / 2;
    canvas.drawLine(Offset(8, mitadY), Offset(size.width - 8, mitadY), linea);

    // Círculo central.
    canvas.drawCircle(Offset(size.width / 2, mitadY), size.width * 0.16, linea);
    canvas.drawCircle(Offset(size.width / 2, mitadY), 2.5, linea..style = PaintingStyle.fill);
    linea.style = PaintingStyle.stroke;

    // Área grande abajo (nuestra portería) y arriba (rival).
    final anchoArea = size.width * 0.6;
    final altoArea = size.height * 0.14;
    canvas.drawRect(
      Rect.fromLTWH((size.width - anchoArea) / 2, size.height - 8 - altoArea, anchoArea, altoArea),
      linea,
    );
    canvas.drawRect(
      Rect.fromLTWH((size.width - anchoArea) / 2, 8, anchoArea, altoArea),
      linea,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Alineación sobre un campo de fútbol: una fila por posición, portero
/// abajo y delanteros arriba (como se ve un equipo desde la grada).
class PitchView extends StatelessWidget {
  final List<LineupPlayer> jugadores;
  final void Function(LineupPlayer)? onTapPlayer;

  const PitchView({super.key, required this.jugadores, this.onTapPlayer});

  List<LineupPlayer> _porPosicion(String posicion) =>
      jugadores.where((j) => j.posicion == posicion).toList();

  @override
  Widget build(BuildContext context) {
    final filas = [
      _porPosicion('DEL'),
      _porPosicion('MED'),
      _porPosicion('DEF'),
      _porPosicion('POR'),
    ].where((fila) => fila.isNotEmpty).toList();

    return AspectRatio(
      aspectRatio: 0.68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1E7D3C), Color(0xFF2A9950)],
                  ),
                ),
                child: CustomPaint(painter: _PitchPainter(), size: Size.infinite),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
                child: Column(
                  children: [
                    for (final fila in filas)
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [for (final jugador in fila) _PlayerChip(jugador: jugador, onTap: onTapPlayer)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Círculo de 36px con foto del jugador (o el fallback de color+letra si no
/// hay foto), con borde blanco y sombra — usado en los chips del campo.
class _ChipAvatar extends StatelessWidget {
  final String fotoUrl;
  final String posicion;

  const _ChipAvatar({required this.fotoUrl, required this.posicion});

  Widget _fallback() => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorForPosicion(posicion),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Text(posicion, style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    if (fotoUrl.isEmpty) return _fallback();
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: ClipOval(
        child: Image.network(
          webSafePhotoUrl(fotoUrl),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, _, _) => _fallback(),
          loadingBuilder: (context, child, progress) => progress == null ? child : _fallback(),
        ),
      ),
    );
  }
}

class _TeamPlayerChip extends StatelessWidget {
  final TeamPlayer jugador;
  final void Function(TeamPlayer)? onTap;

  const _TeamPlayerChip({required this.jugador, this.onTap});

  String _apellido(String nombre) {
    final partes = nombre.split(' ');
    return partes.length > 1 ? partes.last : nombre;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(jugador),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChipAvatar(fotoUrl: jugador.fotoUrl, posicion: jugador.posicion),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 68),
              child: Text(
                _apellido(jugador.nombre),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
            Text(
              '${(jugador.precio / 1000000).toStringAsFixed(1)}M€',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recuentos de defensas/centrocampistas/delanteros por formación — debe
/// coincidir con FORMACIONES en fantasy_assistant/modules/lineup_optimizer.py.
/// El portero (1) no está aquí porque es fijo en todas.
const kFormaciones = {
  '4-3-3': {'DEF': 4, 'MED': 3, 'DEL': 3},
  '4-4-2': {'DEF': 4, 'MED': 4, 'DEL': 2},
  '3-4-3': {'DEF': 3, 'MED': 4, 'DEL': 3},
  '3-5-2': {'DEF': 3, 'MED': 5, 'DEL': 2},
  '5-3-2': {'DEF': 5, 'MED': 3, 'DEL': 2},
  '5-4-1': {'DEF': 5, 'MED': 4, 'DEL': 1},
};

/// Huecos ordenados de una formación, ej. 4-3-3 -> [POR1, DEF1..4, MED1..3, DEL1..3].
List<String> slotsDeFormacion(String formacion) {
  final counts = kFormaciones[formacion] ?? kFormaciones['4-3-3']!;
  return [
    'POR1',
    for (var i = 1; i <= counts['DEF']!; i++) 'DEF$i',
    for (var i = 1; i <= counts['MED']!; i++) 'MED$i',
    for (var i = 1; i <= counts['DEL']!; i++) 'DEL$i',
  ];
}

/// "DEF2" -> "DEF"
String posicionDeSlot(String slot) => slot.replaceAll(RegExp(r'[0-9]'), '');

/// Campo estilo Futbin: huecos fijos según la formación elegida, vacíos o
/// con el jugador que el usuario haya colocado. Tocar cualquier hueco
/// (vacío o lleno) dispara [onTapSlot].
class FormationPitchView extends StatelessWidget {
  final String formacion;
  final Map<String, TeamPlayer> asignados; // slot -> jugador
  final void Function(String slot) onTapSlot;

  const FormationPitchView({super.key, required this.formacion, required this.asignados, required this.onTapSlot});

  @override
  Widget build(BuildContext context) {
    final slots = slotsDeFormacion(formacion);
    final filas = [
      slots.where((s) => posicionDeSlot(s) == 'DEL').toList(),
      slots.where((s) => posicionDeSlot(s) == 'MED').toList(),
      slots.where((s) => posicionDeSlot(s) == 'DEF').toList(),
      slots.where((s) => posicionDeSlot(s) == 'POR').toList(),
    ];

    return AspectRatio(
      aspectRatio: 0.68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1E7D3C), Color(0xFF2A9950)],
                  ),
                ),
                child: CustomPaint(painter: _PitchPainter(), size: Size.infinite),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
                child: Column(
                  children: [
                    for (final fila in filas)
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (final slot in fila)
                              asignados[slot] != null
                                  ? _TeamPlayerChip(jugador: asignados[slot]!, onTap: (_) => onTapSlot(slot))
                                  : _EmptySlotChip(posicion: posicionDeSlot(slot), onTap: () => onTapSlot(slot)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlotChip extends StatelessWidget {
  final String posicion;
  final VoidCallback onTap;

  const _EmptySlotChip({required this.posicion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5, style: BorderStyle.solid),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 2),
            Text(
              posicion,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final LineupPlayer jugador;
  final void Function(LineupPlayer)? onTap;

  const _PlayerChip({required this.jugador, this.onTap});

  String _apellido(String nombre) {
    final partes = nombre.split(' ');
    return partes.length > 1 ? partes.last : nombre;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(jugador),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChipAvatar(fotoUrl: jugador.fotoUrl, posicion: jugador.posicion),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 68),
              child: Text(
                _apellido(jugador.nombre),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
            Text(
              '${(jugador.precio / 1000000).toStringAsFixed(1)}M€',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
