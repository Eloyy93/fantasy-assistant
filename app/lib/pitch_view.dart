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
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorForPosicion(jugador.posicion),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Text(
                jugador.posicion,
                style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800),
              ),
            ),
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
