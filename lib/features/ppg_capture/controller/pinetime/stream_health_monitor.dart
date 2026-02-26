/// Monitor de salud del stream PineTime.
///
/// Evalúa calidad de paquetes entrantes para detectar:
/// - payloads inválidos (muy cortos),
/// - repetición excesiva de paquetes idénticos,
/// - acumulación de misses que amerita resync o error.
import '../../domain/bytes_equal.dart';

enum RawPacketAssessment { ok, invalidPayload, repeatedPayload }

/// Monitorea salud del stream para detectar misses y payloads repetidos.
class StreamHealthMonitor {
  StreamHealthMonitor({
    required this.maxConsecutiveMisses,
    required this.maxSameRaw,
  });

  final int maxConsecutiveMisses;
  final int maxSameRaw;

  int misses = 0;
  int sameRaw = 0;
  List<int>? _lastRaw;

  void reset() {
    misses = 0;
    sameRaw = 0;
    _lastRaw = null;
  }

  RawPacketAssessment assessRaw({
    required List<int> raw,
    required int minPayloadBytes,
  }) {
    if (raw.length < minPayloadBytes) {
      misses++;
      return RawPacketAssessment.invalidPayload;
    }

    misses = 0;

    if (_lastRaw != null && bytesEqual(_lastRaw!, raw)) {
      sameRaw++;
      if (sameRaw >= maxSameRaw) {
        return RawPacketAssessment.repeatedPayload;
      }
      return RawPacketAssessment.ok;
    }

    sameRaw = 0;
    _lastRaw = raw;
    return RawPacketAssessment.ok;
  }

  void registerStreamError() {
    misses++;
  }

  bool get reachedMissLimit => misses >= maxConsecutiveMisses;
}
