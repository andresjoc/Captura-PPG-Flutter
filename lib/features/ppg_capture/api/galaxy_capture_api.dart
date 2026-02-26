/// API de backend para captura PPG desde Galaxy Watch.
///
/// ## Rol arquitectónico
/// Esta clase es una **fachada para la capa UI**:
/// - La UI invoca comandos de alto nivel (`start`, `shareCsv`, `dispose`).
/// - La UI escucha streams ya preparados (`state$`, `errors$`).
///
/// ## Qué NO hace la UI gracias a esta API
/// - No abre ni gestiona `EventChannel` nativo.
/// - No parsea payloads del reloj.
/// - No aplica filtros de señal.
/// - No administra commit/abort de CSV.
///
/// Todo lo anterior vive en controller/domain/data, manteniendo widgets
/// declarativos y fáciles de mantener.

import 'package:flutter/services.dart';

import '../controller/galaxy/galaxy_capture_controller.dart';
import '../data/csv_recorder.dart';
import '../models/galaxy_capture_state.dart';

export '../models/galaxy_capture_state.dart';

/// Entrada pública de captura Galaxy consumida por pantallas Flutter.
class GalaxyCaptureApi {
  /// Construye la API con parámetros de sesión inyectables para test/config.
  GalaxyCaptureApi({
    EventChannel? statusChannel,
    CsvRecorder? recorder,
    this.recordSeconds = 90,
    this.windowSeconds = 8.0,
    DateTime Function()? now,
  }) : _controller = GalaxyCaptureController(
         statusChannel: statusChannel,
         recorder: recorder,
         recordSeconds: recordSeconds,
         windowSeconds: windowSeconds,
         now: now,
       );

  final GalaxyCaptureController _controller;
  final int recordSeconds;
  final double windowSeconds;

  /// Stream de estado agregado listo para render de UI.
  Stream<GalaxyCaptureState> get state$ => _controller.state$;

  /// Stream de errores de negocio/infra para feedback visual.
  Stream<String> get errors$ => _controller.errors$;

  /// Inicia la sesión de captura (suscripción a Data Layer y ciclo interno).
  void start() => _controller.start();

  /// Comparte el CSV confirmado de la sesión si existe.
  Future<void> shareCsv() => _controller.shareCsv();

  /// Libera recursos de la sesión y de los streams.
  Future<void> dispose() => _controller.dispose();
}
