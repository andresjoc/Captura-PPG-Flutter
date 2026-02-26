/// Normalización de lotes para el flujo Galaxy.
///
/// Este archivo encapsula reglas de saneamiento de datos previas al pipeline
/// visual: deduplicación por timestamp, descarte de muestras antiguas y
/// detección de saltos de sesión para reiniciar la gráfica cuando corresponde.
class GalaxyNormalizedBatch {
  const GalaxyNormalizedBatch({
    required this.timestamps,
    required this.values,
    required this.shouldResetChart,
    required this.firstTimestampSec,
    required this.lastTimestampSec,
  });

  final List<double> timestamps;
  final List<double> values;
  final bool shouldResetChart;
  final double firstTimestampSec;
  final double lastTimestampSec;
}

class GalaxyBatchIngestor {
  static const _timestampEpsilonSec = 1e-6;

  /// Convierte un lote crudo en un lote consistente para render/CSV.
  ///
  /// Reglas principales:
  /// - Ignora muestras con timestamp menor o igual al último procesado.
  /// - Si detecta retroceso temporal importante, marca `shouldResetChart`.
  /// - En el primer lote, recorta histórico para iniciar dentro de la ventana
  ///   visible (`windowSeconds`) y evitar una gráfica saturada desde el inicio.
  GalaxyNormalizedBatch? normalize({
    required List<double> incomingTimestamps,
    required List<double> incomingValues,
    required double? firstTimestampSec,
    required double lastTimestampSec,
    required double windowSeconds,
  }) {
    final timestamps = <double>[];
    final values = <double>[];
    final hasLastTimestamp = lastTimestampSec > 0;

    for (
      var i = 0;
      i < incomingTimestamps.length && i < incomingValues.length;
      i++
    ) {
      final ts = incomingTimestamps[i];
      if (hasLastTimestamp && ts <= lastTimestampSec + _timestampEpsilonSec) {
        continue;
      }
      timestamps.add(ts);
      values.add(incomingValues[i]);
    }

    if (timestamps.isEmpty || values.isEmpty) return null;

    final shouldReset =
        firstTimestampSec != null && timestamps.first < lastTimestampSec - 1;

    var resolvedFirstTimestamp = firstTimestampSec;
    if (resolvedFirstTimestamp == null) {
      final latestTs = timestamps.last;
      final minInitialTs = latestTs - windowSeconds;
      var startIndex = 0;
      while (startIndex < timestamps.length && timestamps[startIndex] < minInitialTs) {
        startIndex++;
      }
      if (startIndex > 0) {
        timestamps.removeRange(0, startIndex);
        values.removeRange(0, startIndex);
      }
      if (timestamps.isEmpty || values.isEmpty) return null;
      resolvedFirstTimestamp = timestamps.first;
    }

    return GalaxyNormalizedBatch(
      timestamps: timestamps,
      values: values,
      shouldResetChart: shouldReset,
      firstTimestampSec: resolvedFirstTimestamp,
      lastTimestampSec: timestamps.last,
    );
  }
}
