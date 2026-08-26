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

/// Puntos conseguidos jornada a jornada.
class PointsHistoryChart extends StatelessWidget {
  final List<PointsEntry> puntos;

  const PointsHistoryChart({super.key, required this.puntos});

  @override
  Widget build(BuildContext context) {
    if (puntos.isEmpty) {
      return const _SinDatos('Aún no hay puntos registrados esta temporada.');
    }

    final maxY = puntos.map((p) => p.puntos).reduce((a, b) => a > b ? a : b).toDouble();

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
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
                barRods: [
                  BarChartRodData(
                    toY: puntos[i].puntos.toDouble(),
                    color: puntos[i].puntos >= 0 ? colorForPosicion('DEL') : Colors.grey,
                    width: 14,
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
