/// Ciclo de vida de sesión para captura PineTime.
///
/// Este componente concentra reglas temporales y de persistencia:
/// - apertura de CSV al primer dato válido,
/// - cálculo de tiempo restante,
/// - decisión de cierre por duración configurada,
/// - commit/abort transaccional del archivo.
import '../../data/csv_recorder.dart';

class PinetimeCaptureLifecycle {
  PinetimeCaptureLifecycle({
    required CsvRecorder recorder,
    required DateTime Function() now,
    required int recordSeconds,
  }) : _recorder = recorder,
       _now = now,
       _recordSeconds = recordSeconds;

  final CsvRecorder _recorder;
  final DateTime Function() _now;
  final int _recordSeconds;

  DateTime? _firstValidWall;
  String? _csvPath;
  int _nextSampleIndex = 0;

  DateTime? get firstValidWall => _firstValidWall;
  String? get csvPath => _csvPath;

  void reset() {
    _firstValidWall = null;
    _csvPath = null;
    _nextSampleIndex = 0;
  }

  Future<void> startRecordingIfNeeded({required String prefix}) async {
    if (_firstValidWall != null) return;
    await _recorder.startTemp(prefix: prefix);
    _firstValidWall = _now();
    _nextSampleIndex = 0;
  }

  int? remainingSeconds() {
    if (_firstValidWall == null) return null;
    final elapsed = _now().difference(_firstValidWall!).inSeconds;
    return (_recordSeconds - elapsed).clamp(0, _recordSeconds);
  }

  bool shouldComplete() {
    if (_firstValidWall == null) return false;
    final elapsed = _now().difference(_firstValidWall!).inSeconds;
    return elapsed >= _recordSeconds;
  }

  Future<void> writeSegment({required double dt, required List<int> values}) async {
    if (values.isEmpty) return;
    final t0 = _nextSampleIndex * dt;
    await _recorder.writeSegment(t0: t0, dt: dt, values: values);
    _nextSampleIndex += values.length;
  }

  Future<String?> commit() async {
    _csvPath = await _recorder.commit();
    return _csvPath;
  }

  Future<void> abort({required bool deleteFile}) async {
    await _recorder.abort(deleteFile: deleteFile);
    if (deleteFile) {
      _csvPath = null;
    }
  }
}
