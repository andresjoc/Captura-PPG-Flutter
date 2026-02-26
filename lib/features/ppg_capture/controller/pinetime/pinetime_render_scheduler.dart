/// Scheduler de render para PineTime.
///
/// Convierte el flujo de muestras crudas en segmentos pequeños por tick para
/// mantener animación estable en UI y evitar saltos de consumo de CPU.
import 'dart:collection';

class PinetimeRenderScheduler {
  PinetimeRenderScheduler({required this.dt, required this.renderFps});

  final double dt;
  final int renderFps;

  final Queue<int> _pendingSamples = Queue<int>();
  double _renderBudgetSamples = 0;

  bool get hasPendingSamples => _pendingSamples.isNotEmpty;

  void reset() {
    _pendingSamples.clear();
    _renderBudgetSamples = 0;
  }

  void enqueueAll(List<int> values) {
    _pendingSamples.addAll(values);
  }

  List<int> takeNextTickSegment() {
    if (_pendingSamples.isEmpty) return const [];

    final sampleRateHz = dt > 0 ? (1 / dt) : 0.0;
    if (sampleRateHz <= 0) return const [];

    _renderBudgetSamples += sampleRateHz / renderFps;
    var samplesThisTick = _renderBudgetSamples.floor();
    if (samplesThisTick <= 0) return const [];

    // Suaviza avance visual: como máximo un punto por tick.
    if (samplesThisTick > 1) {
      samplesThisTick = 1;
    }

    if (samplesThisTick > _pendingSamples.length) {
      samplesThisTick = _pendingSamples.length;
    }

    _renderBudgetSamples -= samplesThisTick;

    final segment = <int>[];
    for (var i = 0; i < samplesThisTick; i++) {
      segment.add(_pendingSamples.removeFirst());
    }
    return segment;
  }
}
