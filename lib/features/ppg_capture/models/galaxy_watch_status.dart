/// Modelo tipado del estado recibido por Data Layer de Galaxy Watch.
///
/// Evita manipular mapas dinámicos en UI y expone textos derivados amigables.

class GalaxyWatchStatus {
  const GalaxyWatchStatus({
    required this.watchConnected,
    required this.watchNames,
    required this.ppgSharing,
    required this.lastPpgTimestamp,
    required this.payloadPreview,
    required this.payload,
  });

  const GalaxyWatchStatus.initial()
      : watchConnected = null,
        watchNames = const <String>[],
        ppgSharing = false,
        lastPpgTimestamp = null,
        payloadPreview = '',
        payload = null;

  final bool? watchConnected;
  final List<String> watchNames;
  final bool ppgSharing;
  final int? lastPpgTimestamp;
  final String payloadPreview;
  final String? payload;

  factory GalaxyWatchStatus.fromMap(Map<Object?, Object?> map) {
    return GalaxyWatchStatus(
      watchConnected: map['watchConnected'] as bool?,
      watchNames: (map['watchNames'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      ppgSharing: map['ppgSharing'] as bool? ?? false,
      lastPpgTimestamp: map['lastPpgTimestamp'] as int?,
      payloadPreview: map['payloadPreview'] as String? ?? '',
      payload: map['payload'] as String?,
    );
  }

  String get watchStatusText {
    if (watchConnected == null) {
      return 'Desconocido';
    }
    if (watchConnected == false) {
      return 'No';
    }
    if (watchNames.isNotEmpty) {
      return 'Sí (${watchNames.join(', ')})';
    }
    return 'Sí';
  }

  String get ppgStatusText {
    if (!ppgSharing) {
      return 'No';
    }
    final relative = _relativeTimeString(lastPpgTimestamp);
    if (relative.isEmpty) {
      return 'Sí';
    }
    return 'Sí ($relative)';
  }

  String _relativeTimeString(int? timestampMs) {
    if (timestampMs == null) {
      return '';
    }
    final eventTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = DateTime.now().difference(eventTime);
    if (diff.inSeconds < 60) {
      return 'hace ${diff.inSeconds} s';
    }
    if (diff.inMinutes < 60) {
      return 'hace ${diff.inMinutes} min';
    }
    return 'hace ${diff.inHours} h';
  }
}
