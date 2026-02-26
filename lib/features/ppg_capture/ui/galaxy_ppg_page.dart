/// Vista Galaxy Watch basada en API de backend.
///
/// ## Principio de separación
/// Esta UI es deliberadamente delgada:
/// - no abre canales nativos,
/// - no parsea payloads,
/// - no aplica filtros de señal,
/// - no administra CSV.
///
/// Solo consume el estado consolidado por `GalaxyCaptureApi` y renderiza.

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/galaxy_capture_api.dart';

class GalaxyPpgPage extends StatefulWidget {
  const GalaxyPpgPage({super.key});

  @override
  State<GalaxyPpgPage> createState() => _GalaxyPpgPageState();
}

class _GalaxyPpgPageState extends State<GalaxyPpgPage> {
  /// API de backend para Data Layer + filtrado + CSV.
  late final GalaxyCaptureApi _api;

  StreamSubscription<GalaxyCaptureState>? _stateSub;
  StreamSubscription<String>? _errorSub;

  // Estado agregado entregado por backend (listo para UI).
  GalaxyCaptureState _state = GalaxyCaptureState.initial();

  @override
  void initState() {
    super.initState();
    _api = GalaxyCaptureApi();

    // Estado agregado del backend (watch status, canal, señal y progreso).
    _stateSub = _api.state$.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });

    // Canal de errores funcionales para feedback visual.
    _errorSub = _api.errors$.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });

    _api.start();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _errorSub?.cancel();
    _api.dispose();
    super.dispose();
  }

  String _watchTitle() {
    if (_state.watchStatus.watchNames.isNotEmpty) {
      return _state.watchStatus.watchNames.first;
    }
    return 'Galaxy Watch';
  }

  String _subtitle() {
    if (_state.completed) {
      return '✅ Completado. CSV listo para compartir.';
    }
    if (_state.remainingSeconds != null) {
      return 'Grabando… restante: ${_state.remainingSeconds}s';
    }
    return _state.watchStatus.ppgStatusText;
  }

  @override
  Widget build(BuildContext context) {
    // La UI calcula viewport visual; la señal ya viene procesada por API.
    final windowSeconds = _api.windowSeconds;
    final spots = _state.spots;
    final maxX = spots.isNotEmpty ? spots.last.x : 0.0;
    final minX = (maxX - windowSeconds) < 0 ? 0.0 : (maxX - windowSeconds);
    final displayedSpots = spots
        .where((s) => s.x >= minX)
        .map((s) => FlSpot(s.x - minX, s.y))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_watchTitle()),
        actions: [
          IconButton(
            tooltip: 'Compartir CSV',
            icon: const Icon(Icons.share),
            onPressed: _api.shareCsv,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Resumen operativo de Data Layer y estado de la sesión.
            Card(
              child: ListTile(
                title: Text('Galaxy Watch • ${_subtitle()}'),
                subtitle: Text(
                  'Conectado: ${_state.watchStatus.watchStatusText}\n'
                  'Canal: ${_state.channelName}\n',
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Layout responsivo para preservar legibilidad del chart.
            LayoutBuilder(
              builder: (context, constraints) {
                final chartWidth = constraints.maxWidth.floorToDouble();
                final desiredHeight = chartWidth * 0.58;
                final maxHeight = (constraints.maxHeight - 8).clamp(180.0, 340.0);
                final chartHeight = desiredHeight.clamp(180.0, maxHeight).floorToDouble();

                return SizedBox(
                  width: chartWidth,
                  height: chartHeight,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: spots.isEmpty
                          ? const Center(
                              child: Text('Esperando datos PPG del Galaxy Watch…'),
                            )
                          : LineChart(
                              duration: Duration.zero,
                              curve: Curves.linear,
                              LineChartData(
                                minX: 0,
                                maxX: windowSeconds,
                                minY: _state.minY,
                                maxY: _state.maxY,
                                titlesData: const FlTitlesData(show: false),
                                gridData: const FlGridData(show: true),
                                borderData: FlBorderData(show: true),
                                lineTouchData: const LineTouchData(enabled: false),
                                clipData: const FlClipData.all(),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: displayedSpots,
                                    isCurved: false,
                                    isStrokeCapRound: true,
                                    barWidth: 2.2,
                                    dotData: const FlDotData(show: false),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
