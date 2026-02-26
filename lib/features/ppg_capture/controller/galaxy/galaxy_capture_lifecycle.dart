/// Ciclo de vida de captura para el flujo Galaxy.
///
/// Gestiona el estado temporal de una sesión de grabación:
/// - inicio real al recibir el primer dato válido,
/// - cálculo de tiempo restante,
/// - escritura/commit/abort de CSV con consistencia.
import '../../data/csv_recorder.dart';

class GalaxyCaptureLifecycle {
  GalaxyCaptureLifecycle({
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
  bool _captureCompleted = false;
  String? _csvPath;

  bool get captureCompleted => _captureCompleted;

  int? getRemainingSeconds() {
    if (_firstValidWall == null) return null;
    final elapsed = _now().difference(_firstValidWall!).inSeconds;
    return (_recordSeconds - elapsed).clamp(0, _recordSeconds);
  }

  bool shouldComplete() {
    if (_firstValidWall == null) return false;
    final elapsed = _now().difference(_firstValidWall!).inSeconds;
    return elapsed >= _recordSeconds;
  }

  void markDataReceived() {
    _firstValidWall ??= _now();
  }

  void reset() {
    _firstValidWall = null;
    _captureCompleted = false;
    _csvPath = null;
  }

  Future<void> writeCsv({
    required List<double> timestamps,
    required List<double> values,
  }) async {
    await _ensureRecorder();
    await _recorder.writeSamples(timestampsSec: timestamps, values: values);
  }

  Future<String?> commit() async {
    if (_csvPath != null) return _csvPath;
    _csvPath = await _recorder.commit();
    return _csvPath;
  }

  Future<void> complete() async {
    _captureCompleted = true;
    if (_recorder.isRecording) {
      _csvPath = await _recorder.commit();
    }
  }

  Future<void> abort() => _recorder.abort(deleteFile: false);

  Future<void> _ensureRecorder() async {
    if (_recorder.isRecording) return;
    await _recorder.startTemp(prefix: 'ppg_galaxy');
    _csvPath = null;
  }
}
