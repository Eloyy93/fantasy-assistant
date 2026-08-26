import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';

class _SinDatos extends StatelessWidget {
  final String mensaje;
  const _SinDatos(this.mensaje);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          mensaje,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Evolución del precio del jugador día a día.
class PriceHistoryChart extends StatelessWidget {
  final List<PricePoint> precios;

  const PriceHistoryChart({super.key, required this.precios});

  @override
  Widget build(BuildContext context) {
    if (precios.length < 2) {
      return const _SinDatos('Aún no hay suficiente historial de precio.\nVuelve en unos días.');
    }

    final spots = [
      for (var i = 0; i < precios.length; i++) FlSpot(i.toDouble(), precios[i].precio / 1000000),
    ];
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final margen = ((maxY - minY) * 0.15).clamp(0.05, double.infinity);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: minY - margen,
          maxY: maxY + margen,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (precios.length / 4).clamp(1, double.infinity).roundToDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= precios.length) return const SizedBox.shrink();
                  final fecha = precios[idx].fecha;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${fecha.day}/${fecha.month}', style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(1)}M', style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: colorForPosicion('MED'),
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: colorForPosicion('MED').withValues(alpha: 0.15)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Color según el rendimiento de la jornada: rojo (mala) -> ámbar -> verde (gran actuación).
Color _colorForPuntos(int puntos) {
  if (puntos >= 8) return const Color(0xFF1D9E4B); // gran actuación
  if (puntos >= 4) return colorForPosicion('MED');
  if (puntos >= 1) return const Color(0xFFE8A63C); // discreta
  return colorForPosicion('DEL'); // mala o no jugó
}

/// Puntos conseguidos jornada a jornada, con el valor exacto encima de cada
/// barra y color según lo buena que fue la actuación.
class PointsHistoryChart extends StatelessWidget {
  final List<PointsEntry> puntos;

  const PointsHistoryChart({super.key, required this.puntos});

  @override
  Widget build(BuildContext context) {
    if (puntos.isEmpty) {
      return const _SinDatos('Aún no hay puntos registrados esta temporada.');
    }

    final maxPuntos = puntos.map((p) => p.puntos).reduce((a, b) => a > b ? a : b);
    final maxY = maxPuntos <= 0 ? 1.0 : maxPuntos * 1.35;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: false,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.transparent,
              tooltipPadding: EdgeInsets.zero,
              tooltipMargin: 4,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                rod.toY.toInt().toString(),
                const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, m) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10))),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= puntos.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('J${puntos[idx].jornada}', style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < puntos.length; i++)
              BarChartGroupData(
                x: i,
                showingTooltipIndicators: [0],
                barRods: [
                  BarChartRodData(
                    toY: puntos[i].puntos.toDouble(),
                    color: _colorForPuntos(puntos[i].puntos),
                    width: 16,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
