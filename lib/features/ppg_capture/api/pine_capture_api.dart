/// API de backend para captura PineTime.
///
/// ## Rol arquitectónico
/// Esta API existe para mantener la UI desacoplada de la lógica de captura.
/// La pantalla consume únicamente:
/// - streams (`status$`, `spots$`),
/// - acciones de alto nivel (`start`, `resync`, `shareCsvIfAvailable`).
///
/// ## Delimitación de responsabilidades
/// - **UI**: renderiza widgets, escucha streams y muestra feedback.
/// - **API/Controller**: conexión BLE, priming, salud de stream, filtros,
///   escritura y cierre de CSV.
///
/// Con esta separación, cambios en protocolo/driver no exigen reescribir la UI.

import 'package:fl_chart/fl_chart.dart';

import '../controller/pinetime/pinetime_capture_controller.dart';
import '../data/ble_service.dart';
import '../data/csv_recorder.dart';
import '../domain/ppg_aggregator.dart';
import '../drivers/pinetime_driver.dart';
import '../models/capture_status.dart';

/// Fachada principal consumida por `PpgPage` para captura PineTime.
class PineCaptureApi {
  /// Construye la API de backend para PineTime con defaults de captura.
  ///
  /// Valores relevantes para visualización/sesión:
  /// - `recordSeconds=90`: duración total esperada.
  /// - `windowSeconds`: ventana visible del chart.
  /// - `renderFps`: cadencia de actualización visual.
  /// - `dt=0.1`: base temporal de muestras para CSV/plot.
  PineCaptureApi({
    BleService? ble,
    CsvRecorder? recorder,
    this.windowSeconds = 7,
    this.renderFps = 8,
  }) : _controller = PinetimeCaptureController(
         ble: ble ?? BleService(),
         recorder: recorder ?? CsvRecorder(),
         driver: PineTimeDriver(),
         aggregator: PpgAggregator(),
         pollMs: 1000,
         recordSeconds: 90,
         windowSeconds: windowSeconds,
         renderFps: renderFps,
         dt: 0.1,
       );

  final PinetimeCaptureController _controller;
  final double windowSeconds;
  final int renderFps;

  /// Stream de estado de sesión para badges, mensajes y métricas de diagnóstico.
  Stream<CaptureStatus> get status$ => _controller.status$;

  /// Stream de puntos ya procesados, listos para `LineChart`.
  Stream<List<FlSpot>> get spots$ => _controller.spots$;

  /// Inicia captura para un `deviceId` BLE seleccionado por UI.
  Future<void> start({required String deviceId}) {
    return _controller.start(deviceId: deviceId);
  }

  /// Fuerza resincronización (reinicia buffers, priming y estado operativo).
  Future<void> resync() => _controller.resync();

  /// Comparte CSV si existe una sesión confirmada.
  Future<void> shareCsvIfAvailable() => _controller.shareCsvIfAvailable();

  /// Libera recursos (subscripciones/streams/archivos temporales).
  Future<void> dispose() => _controller.dispose();
}
