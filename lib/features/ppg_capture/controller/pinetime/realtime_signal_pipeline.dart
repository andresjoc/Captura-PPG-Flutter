/// Pipeline de señal en tiempo real para la captura PPG.
///
/// Responsabilidad:
/// - deduplicar segmento incremental cuando hay agregación,
/// - aplicar filtrado causal muestra-a-muestra,
/// - mantener ventana deslizante para la gráfica.
///
/// El controller principal delega aquí toda la matemática de serie temporal
/// para enfocarse en orquestación de sesión (BLE, estado, CSV y errores).

import 'package:fl_chart/fl_chart.dart';

import '../../domain/ppg_aggregator.dart';
import '../../drivers/ppg_device_driver.dart';
import 'streaming_filters.dart';

class RealtimeSignalPipeline {
  RealtimeSignalPipeline({
    required this.dt,
    required this.windowSeconds,
    required this.lowCutHz,
    required this.highCutHz,
    this.warmupSeconds = 0.1,
  }) : assert(dt > 0, 'dt must be > 0') {
    _warmupSamples = (warmupSeconds / dt).round().clamp(1, 1000000);
    _rebuildFilters();
  }

  final double dt;
  final double windowSeconds;
  final double lowCutHz;
  final double highCutHz;
  final double warmupSeconds;

  late final int _warmupSamples;

  double _processFsHz = 10.0;
  late StreamingBandpassFilter _streamFilter;
  late DcBlocker _dcBlocker;

  int _prevLen = 0;
  double _t = 0.0;
  int _warmupCount = 0;
  bool _filtersPrimed = false;
  final List<FlSpot> _spots = [];

  List<FlSpot> get spots => List<FlSpot>.from(_spots);

  void reset({PpgAggregator? aggregator}) {
    _prevLen = 0;
    _t = 0.0;
    _warmupCount = 0;
    _filtersPrimed = false;
    _spots.clear();
    aggregator?.reset();
    _rebuildFilters();
  }

  /// Devuelve solo las muestras nuevas y estables para persistencia/plot.
  List<int> extractNewSegment({
    required PpgDeviceDriver driver,
    required PpgAggregator? aggregator,
    required List<int> decodedSamples,
  }) {
    if (!driver.needsAggregation) {
      return decodedSamples;
    }

    final agg = aggregator!.push(decodedSamples);
    final safeEnd = agg.length - driver.safetyTail;
    if (safeEnd <= 0) return const [];

    final start = _prevLen.clamp(0, safeEnd);
    final end = safeEnd;
    if (end <= start) return const [];

    _prevLen = end;
    return agg.sublist(start, end);
  }

  /// Procesa segmento completo y actualiza spots visibles.
  void appendSegment(List<int> segment) {
    if (!_filtersPrimed && segment.isNotEmpty) {
      _primeFilters(segment);
      _filtersPrimed = true;
    }

    for (final v in segment) {
      final processed = _nextProcessedValue(v.toDouble());
      if (processed != null) {
        _spots.add(FlSpot(_t, processed));
      }
      _t += dt;
    }

    final minKeepX = _t - windowSeconds;
    while (_spots.isNotEmpty && _spots.first.x < minKeepX) {
      _spots.removeAt(0);
    }
  }

  void _rebuildFilters() {
    _processFsHz = (dt > 0) ? (1.0 / dt) : 20.0;
    _streamFilter = StreamingBandpassFilter(
      fs: _processFsHz,
      lowcutHz: lowCutHz,
      highcutHz: highCutHz,
    );
    _dcBlocker = DcBlocker(fs: _processFsHz, cutoffHz: 0.15);
  }

  double? _nextProcessedValue(double sample) {
    _warmupCount++;
    // Warmup temporal para suprimir artefactos de arranque no fisiológicos
    // antes de emitir señal útil a la gráfica.
    if (_warmupCount <= _warmupSamples) {
      return null;
    }

    final x = _dcBlocker.step(sample);
    return _streamFilter.step(x);
  }

  /// Inicializa estados internos con una semilla estable para evitar
  /// transitorios artificiales repetibles al inicio de cada sesión.
  void _primeFilters(List<int> firstSegment) {
    const seedWindow = 8;
    const settleSteps = 64;
    final take = firstSegment.length < seedWindow
        ? firstSegment.length
        : seedWindow;
    final seed =
        firstSegment.take(take).fold<double>(0.0, (acc, v) => acc + v) / take;

    for (var i = 0; i < settleSteps; i++) {
      final x = _dcBlocker.step(seed);
      _streamFilter.step(x);
    }
  }
}
