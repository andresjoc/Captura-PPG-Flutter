/// Servicio de persistencia CSV transaccional.
///
/// Escribe primero en archivo temporal y solo confirma al finalizar para evitar
/// datasets corruptos si la sesión se corta a mitad.

import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Grabador CSV transaccional para sesiones PPG.
///
/// Estrategia:
/// - escribe primero en `*.tmp.csv`,
/// - confirma con rename atómico a `*.csv` al finalizar,
/// - permite abortar y limpiar archivos temporales incompletos.
class CsvRecorder {
  File? _file;
  IOSink? _sink;
  String? filePath;

  bool get isRecording => _sink != null;

  Future<void> startTemp({String prefix = "ppg"}) async {
    // Siempre inicia en estado limpio para no mezclar sesiones.
    await abort(deleteFile: true);

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final path = '${dir.path}/${prefix}_${ts}.tmp.csv';

    _file = File(path);
    filePath = path;

    _sink = _file!.openWrite(mode: FileMode.write);
    _sink!.writeln('time,value');
    await _sink!.flush();
  }

  Future<void> writeSegment({
    required double t0,
    required double dt,
    required List<int> values,
  }) async {
    // Escritura incremental para flujos enteros (lecturas sin procesar).
    final sink = _sink;
    if (sink == null) return;

    for (var i = 0; i < values.length; i++) {
      final t = t0 + i * dt;
      sink.writeln('${t.toStringAsFixed(6)},${values[i]}');
    }
    await sink.flush();
  }

  Future<void> writeSamples({
    required List<double> timestampsSec,
    required List<double> values,
  }) async {
    // Escritura incremental para muestras ya normalizadas en double.
    final sink = _sink;
    if (sink == null) return;

    final length =
        timestampsSec.length < values.length ? timestampsSec.length : values.length;

    for (var i = 0; i < length; i++) {
      sink.writeln(
        '${timestampsSec[i].toStringAsFixed(6)},${values[i].toStringAsFixed(6)}',
      );
    }
    await sink.flush();
  }

  Future<String?> commit() async {
    // Confirmación de sesión: se cierra `tmp` y se publica como `.csv` final.
    final f = _file;
    final sink = _sink;
    if (f == null || sink == null) return null;

    await sink.flush();
    await sink.close();
    _sink = null;

    final finalPath = f.path.replaceAll('.tmp.csv', '.csv');
    final finalFile = await f.rename(finalPath);

    _file = finalFile;
    filePath = finalFile.path;
    return filePath;
  }

  Future<void> abort({bool deleteFile = true}) async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;

    final f = _file;
    final path = filePath;

    _file = null;
    filePath = null;

    if (!deleteFile) return;

    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}

    if (f == null && path != null) {
      try {
        final ff = File(path);
        if (await ff.exists()) await ff.delete();
      } catch (_) {}
    }
  }
}
