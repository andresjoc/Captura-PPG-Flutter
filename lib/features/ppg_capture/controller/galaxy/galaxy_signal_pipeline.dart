/// Pipeline de señal para visualización en tiempo real del flujo Galaxy.
///
/// Responsabilidades:
/// - Bufferizar muestras crudas entrantes.
/// - Aplicar filtrado pasa-banda en streaming.
/// - Mantener una ventana deslizante para la gráfica.
/// - Estabilizar el rango vertical (Y) para evitar saltos bruscos.
import 'dart:collection';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

class GalaxySignalPipeline {
  static const _filterFsHz = 25.0;
  static const _filterLowcutHz = 0.5;
  static const _filterHighcutHz = 8.0;
  static const _filterWarmupSamples = 50;
  static const _filterSettleSamples = 48;
  static const _maxSamplesPerRenderTick = 2;
  static const _renderDtSec = 1 / _filterFsHz;
  static const _yRangeLerpFactor = 0.18;
  static const _minVisualRange = 80.0;
  static const _chartVerticalPaddingFactor = 0.4;

  /// Cola de muestras pendientes de procesar para desacoplar ingestión/render.
  final Queue<double> _pendingSamples = Queue<double>();
  List<FlSpot> _displaySpots = [];
  double _renderXSec = 0;
  var _ingestedSamples = 0;
  late _StreamingBandpassFilter _streamingFilter = _createStreamingFilter();
  bool _filtersPrimed = false;
  double? _firstSampleValue;
  double? _stableMinY;
  double? _stableMaxY;

  List<FlSpot> get spots => List<FlSpot>.unmodifiable(_displaySpots);
  double get minY => _stableMinY ?? -100;
  double get maxY => _stableMaxY ?? 100;

  /// Añade nuevas muestras al buffer pendiente.
  void enqueue(Iterable<double> values) {
    for (final value in values) {
      _firstSampleValue ??= value;
      _pendingSamples.add(value);
    }
  }

  bool get hasPendingSamples => _pendingSamples.isNotEmpty;

  /// Procesa una pequeña porción de muestras para mantener UI fluida.
  ///
  /// Este drenado incremental evita bloquear el hilo principal cuando llegan
  /// lotes grandes desde el Data Layer del reloj.
  void drain({required double windowSeconds}) {
    if (_pendingSamples.isEmpty) return;

    if (!_filtersPrimed && _firstSampleValue != null) {
      _primeFilters(_firstSampleValue!);
      _filtersPrimed = true;
    }

    var drained = 0;
    while (_pendingSamples.isNotEmpty && drained < _maxSamplesPerRenderTick) {
      final sample = _pendingSamples.removeFirst();
      final filteredValue = _streamingFilter.process(sample);

      if (_ingestedSamples >= _filterWarmupSamples) {
        _displaySpots.add(FlSpot(_renderXSec, filteredValue));
        _renderXSec += _renderDtSec;
      }

      _ingestedSamples++;
      drained++;
    }

    final minKeepX =
        (_displaySpots.isNotEmpty ? _displaySpots.last.x : 0) - windowSeconds;
    _displaySpots = _displaySpots.where((s) => s.x >= minKeepX).toList();
    _resolveStableYRange();
  }

  /// Reinicia por completo el estado del pipeline y filtros internos.
  void reset() {
    _pendingSamples.clear();
    _displaySpots = [];
    _renderXSec = 0;
    _ingestedSamples = 0;
    _streamingFilter = _createStreamingFilter();
    _filtersPrimed = false;
    _firstSampleValue = null;
    _stableMinY = null;
    _stableMaxY = null;
  }

  void _primeFilters(double sample) {
    for (var i = 0; i < _filterSettleSamples; i++) {
      _streamingFilter.process(sample);
    }
  }

  _StreamingBandpassFilter _createStreamingFilter() {
    return _StreamingBandpassFilter(
      fs: _filterFsHz,
      lowcutHz: _filterLowcutHz,
      highcutHz: _filterHighcutHz,
    );
  }

  void _resolveStableYRange() {
    if (_displaySpots.isEmpty) return;

    final sorted = _displaySpots.map((p) => p.y).toList()..sort();
    final lowIndex = (sorted.length * 0.05).floor().clamp(0, sorted.length - 1);
    final highIndex = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    final low = sorted[lowIndex];
    final high = sorted[highIndex];
    final center = (low + high) / 2;
    final halfSpan = ((high - low) / 2).clamp(
      _minVisualRange / 2,
      double.infinity,
    );
    final paddedHalfSpan = halfSpan * (1 + _chartVerticalPaddingFactor);
    final targetMin = center - paddedHalfSpan;
    final targetMax = center + paddedHalfSpan;

    _stableMinY = _stableMinY == null
        ? targetMin
        : _lerp(_stableMinY!, targetMin, _yRangeLerpFactor);
    _stableMaxY = _stableMaxY == null
        ? targetMax
        : _lerp(_stableMaxY!, targetMax, _yRangeLerpFactor);
  }

  double _lerp(double a, double b, double t) => a + ((b - a) * t);
}

class _StreamingBandpassFilter {
  _StreamingBandpassFilter({
    required double fs,
    required double lowcutHz,
    required double highcutHz,
  }) : _sections = [
         for (final q in _qValues) _RealtimeBiquad.highpass(fs, lowcutHz, q),
         for (final q in _qValues) _RealtimeBiquad.lowpass(fs, highcutHz, q),
       ];

  static const List<double> _qValues = [0.541196100146197, 1.3065629648763766];

  final List<_RealtimeBiquad> _sections;

  double process(double input) {
    var value = input;
    for (final section in _sections) {
      value = section.process(value);
    }
    return value;
  }
}

class _RealtimeBiquad {
  _RealtimeBiquad({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  factory _RealtimeBiquad.lowpass(double fs, double f0, double q) {
    final w0 = 2 * math.pi * f0 / fs;
    final c = math.cos(w0);
    final s = math.sin(w0);
    final alpha = s / (2 * q);
    final b0 = (1 - c) / 2;
    final b1 = 1 - c;
    final b2 = (1 - c) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * c;
    final a2 = 1 - alpha;
    return _RealtimeBiquad(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }

  factory _RealtimeBiquad.highpass(double fs, double f0, double q) {
    final w0 = 2 * math.pi * f0 / fs;
    final c = math.cos(w0);
    final s = math.sin(w0);
    final alpha = s / (2 * q);
    final b0 = (1 + c) / 2;
    final b1 = -(1 + c);
    final b2 = (1 + c) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * c;
    final a2 = 1 - alpha;
    return _RealtimeBiquad(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;

  double process(double input) {
    final out = b0 * input + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = input;
    _y2 = _y1;
    _y1 = out;
    return out;
  }
}
