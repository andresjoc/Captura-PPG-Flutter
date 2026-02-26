/// Modelo de estado observable de la sesión de captura.
///
/// Centraliza fase, métricas de calidad y metadatos para que la UI renderice
/// comportamiento sin inferencias frágiles.

/// Estados de alto nivel de la captura.
enum CapturePhase {
  disconnected,
  connecting,
  priming,
  waitingFirstData,
  recording,
  completed,
  error,
}

/// Estado observable para la UI.
/// La UI no debe inferir estados por “si hay datos o no”,
/// sino escuchar este objeto.
class CaptureStatus {
  final CapturePhase phase;

  /// Nombre “humano” del driver actual (Pinetime, etc.)
  final String driverName;

  /// Segundos restantes (solo en recording).
  final int remainingSeconds;

  /// Errores/paquetes inválidos consecutivos.
  final int misses;

  /// Paquetes idénticos consecutivos detectados (para “stream pegado”).
  final int sameRaw;

  /// Último instante en que una lectura respondió.
  final DateTime? lastReadWall;

  /// Último instante en que se recibió un paquete válido.
  final DateTime? lastValidWall;

  /// Mensaje de error si phase==error.
  final String? error;

  /// CSV final (solo cuando phase==completed).
  final String? csvPath;

  const CaptureStatus({
    required this.phase,
    required this.driverName,
    required this.remainingSeconds,
    required this.misses,
    required this.sameRaw,
    required this.lastReadWall,
    required this.lastValidWall,
    required this.error,
    required this.csvPath,
  });

  factory CaptureStatus.initial({String driverName = 'Unknown'}) =>
      CaptureStatus(
        phase: CapturePhase.disconnected,
        driverName: driverName,
        remainingSeconds: 0,
        misses: 0,
        sameRaw: 0,
        lastReadWall: null,
        lastValidWall: null,
        error: null,
        csvPath: null,
      );

  CaptureStatus copyWith({
    CapturePhase? phase,
    String? driverName,
    int? remainingSeconds,
    int? misses,
    int? sameRaw,
    DateTime? lastReadWall,
    DateTime? lastValidWall,
    String? error,
    String? csvPath,
  }) {
    return CaptureStatus(
      phase: phase ?? this.phase,
      driverName: driverName ?? this.driverName,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      misses: misses ?? this.misses,
      sameRaw: sameRaw ?? this.sameRaw,
      lastReadWall: lastReadWall ?? this.lastReadWall,
      lastValidWall: lastValidWall ?? this.lastValidWall,
      error: error,
      csvPath: csvPath ?? this.csvPath,
    );
  }
}
