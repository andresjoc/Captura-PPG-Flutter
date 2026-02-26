/// Vista PineTime que consume la API de backend.
///
/// ## Principio de separación
/// Este widget NO implementa lógica de captura ni DSP.
/// Solo:
/// - se suscribe a streams expuestos por `PineCaptureApi`,
/// - traduce estado a componentes visuales,
/// - dispara acciones de alto nivel (resync/share).
///
/// Toda lógica de conexión BLE, priming, filtros y CSV vive en backend.

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../api/pine_capture_api.dart';
import '../models/capture_status.dart';

class PpgPage extends StatefulWidget {
  const PpgPage({super.key, required this.device});
  final DiscoveredDevice device;

  @override
  State<PpgPage> createState() => _PpgPageState();
}

class _PpgPageState extends State<PpgPage> {
  /// API de backend (orquesta BLE/captura/CSV).
  ///
  /// Esta UI solo observa streams y dispara acciones de alto nivel.
  late final PineCaptureApi _api;

  StreamSubscription<CaptureStatus>? _statusSub;
  StreamSubscription<List<FlSpot>>? _spotsSub;

  // Estado operativo de la sesión (conexión, priming, recording, etc.).
  CaptureStatus _status = CaptureStatus.initial(driverName: 'PineTime');
  // Serie lista para pintar en la gráfica (ya procesada por backend).
  List<FlSpot> _spots = [];

  // Rango Y estabilizado para evitar temblor visual por autoescalado agresivo.
  double? _displayMinY;
  double? _displayMaxY;

  // Viewport X estabilizado para reducir vibración durante el scroll.
  double _displayMinX = 0;
  double _displayMaxX = 0;

  @override
  void initState() {
    super.initState();
    _api = PineCaptureApi();

    // La UI consume un stream de estado ya consolidado por backend.
    _statusSub = _api.status$.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);

      if (s.phase == CapturePhase.error && s.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.error!)));
      }
      if (s.phase == CapturePhase.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Grabación completa. CSV listo.')),
        );
      }
    });

    // La UI consume spots ya filtrados/listos para plotting.
    _spotsSub = _api.spots$.listen((spots) {
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _updateStableYRange(spots);
        _updateStableXRange();
      });
    });

    _api.start(deviceId: widget.device.id);
  }

  /// Ajuste visual de rango Y con suavizado EMA para evitar "flicker".
  void _updateStableYRange(List<FlSpot> spots) {
    if (spots.isEmpty) {
      _displayMinY = null;
      _displayMaxY = null;
      return;
    }

    var rawMinY = spots.first.y;
    var rawMaxY = spots.first.y;
    for (final p in spots) {
      if (p.y < rawMinY) rawMinY = p.y;
      if (p.y > rawMaxY) rawMaxY = p.y;
    }

    final rawRange = (rawMaxY - rawMinY).abs();
    final padding = (rawRange * 0.12).clamp(20.0, 140.0);
    final targetMinY = rawMinY - padding;
    final targetMaxY = rawMaxY + padding;

    if (_displayMinY == null || _displayMaxY == null) {
      _displayMinY = targetMinY;
      _displayMaxY = targetMaxY;
      return;
    }

    // EMA: se mueve más rápido al expandir rango y más lento al contraerlo.
    final minGrowAlpha = 0.35;
    final minShrinkAlpha = 0.08;
    final maxGrowAlpha = 0.35;
    final maxShrinkAlpha = 0.08;

    final minAlpha = targetMinY < _displayMinY! ? minGrowAlpha : minShrinkAlpha;
    final maxAlpha = targetMaxY > _displayMaxY! ? maxGrowAlpha : maxShrinkAlpha;

    final currentRange = (_displayMaxY! - _displayMinY!).abs();
    final targetRange = (targetMaxY - targetMinY).abs();
    final driftDeadband = (currentRange * 0.015).clamp(1.0, 8.0);
    if ((targetRange - currentRange).abs() < driftDeadband) {
      return;
    }

    _displayMinY = _displayMinY! + (targetMinY - _displayMinY!) * minAlpha;
    _displayMaxY = _displayMaxY! + (targetMaxY - _displayMaxY!) * maxAlpha;
  }

  /// Ajuste visual de ventana X para seguir el stream con suavizado.
  void _updateStableXRange() {
    final targetMaxX = _spots.isNotEmpty ? _spots.last.x : 0.0;
    final targetMinX = (targetMaxX - _api.windowSeconds) < 0
        ? 0.0
        : (targetMaxX - _api.windowSeconds);

    if (_displayMaxX == 0 && _displayMinX == 0) {
      _displayMaxX = targetMaxX;
      _displayMinX = targetMinX;
      return;
    }

    final delta = targetMaxX - _displayMaxX;
    final deadband = (_api.windowSeconds * 0.003).clamp(0.01, 0.06);
    if (delta.abs() <= deadband) {
      return;
    }

    final followAlpha = delta > 0 ? 0.6 : 0.2;
    _displayMaxX += delta * followAlpha;
    _displayMinX = (_displayMaxX - _api.windowSeconds).clamp(0.0, _displayMaxX);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _spotsSub?.cancel();
    _api.dispose();
    super.dispose();
  }

  String _subtitle() {
    switch (_status.phase) {
      case CapturePhase.connecting:
        return 'Conectando…';
      case CapturePhase.priming:
        return 'Enganchando al stream… (priming)';
      case CapturePhase.waitingFirstData:
        return 'Esperando primer dato válido…';
      case CapturePhase.recording:
        return 'Grabando… restante: ${_status.remainingSeconds}s';
      case CapturePhase.completed:
        return '✅ Completado. CSV listo para compartir.';
      case CapturePhase.error:
        return _status.error ?? 'Error';
      case CapturePhase.disconnected:
      default:
        return 'Desconectado';
    }
  }

  @override
  Widget build(BuildContext context) {
    // La UI solo define viewport del chart; backend entrega señal lista.
    final maxX = _displayMaxX;
    final minX = _displayMinX;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.device.name.isNotEmpty ? widget.device.name : widget.device.id,
        ),
        actions: [
          IconButton(
            tooltip: 'Re-sincronizar',
            icon: const Icon(Icons.sync),
            onPressed: _api.resync,
          ),
          IconButton(
            tooltip: 'Compartir CSV',
            icon: const Icon(Icons.share),
            onPressed: _api.shareCsvIfAvailable,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Tarjeta de telemetría de sesión para diagnóstico rápido.
            Card(
              child: ListTile(
                title: Text('${_status.driverName} • ${_subtitle()}'),
                subtitle: Text('misses=${_status.misses} • sameRaw=${_status.sameRaw}\n'),
              ),
            ),
            const SizedBox(height: 12),
            // LayoutBuilder: mantiene proporción consistente del chart.
            LayoutBuilder(
              builder: (context, constraints) {
                final chartWidth = constraints.maxWidth;
                final desiredHeight = chartWidth * 0.58;
                final maxHeight = (constraints.maxHeight - 8).clamp(
                  180.0,
                  340.0,
                );
                final chartHeight = desiredHeight.clamp(180.0, maxHeight);

                return SizedBox(
                  width: chartWidth,
                  height: chartHeight,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _spots.isEmpty
                          ? const Center(child: Text('Esperando datos PPG…'))
                          : LineChart(
                              duration: Duration.zero,
                              curve: Curves.linear,
                              LineChartData(
                                minX: minX,
                                maxX: maxX,
                                minY: _displayMinY,
                                maxY: _displayMaxY,
                                titlesData: const FlTitlesData(show: false),
                                gridData: const FlGridData(show: true),
                                borderData: FlBorderData(show: true),
                                lineTouchData: const LineTouchData(enabled: false),
                                clipData: const FlClipData.all(),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _spots,
                                    isCurved: false,
                                    curveSmoothness: 0.25,
                                    preventCurveOverShooting: true,
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
