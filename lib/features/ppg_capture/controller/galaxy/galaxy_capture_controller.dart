/// Controlador principal de captura para dispositivos Galaxy Watch.
///
/// Orquesta la sesión end-to-end:
/// - suscripción al EventChannel nativo,
/// - parseo e ingestión de batches,
/// - actualización de estado para UI,
/// - control de render periódico,
/// - cierre/commit de captura al cumplir el tiempo objetivo.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/csv_recorder.dart';
import '../../domain/galaxy_payload_parser.dart';
import '../../models/galaxy_capture_state.dart';
import '../../models/galaxy_watch_status.dart';
import 'galaxy_batch_ingestor.dart';
import 'galaxy_capture_lifecycle.dart';
import 'galaxy_signal_pipeline.dart';

class GalaxyCaptureController {
  GalaxyCaptureController({
    EventChannel? statusChannel,
    CsvRecorder? recorder,
    this.recordSeconds = 90,
    this.windowSeconds = 8.0,
    DateTime Function()? now,
  }) : _statusChannel = statusChannel ?? const EventChannel('ppg_events'),
       _recorder = recorder ?? CsvRecorder(),
       _now = now ?? DateTime.now {
    _lifecycle = GalaxyCaptureLifecycle(
      recorder: _recorder,
      now: _now,
      recordSeconds: recordSeconds,
    );
  }

  static const _renderFps = 12;

  final EventChannel _statusChannel;
  final CsvRecorder _recorder;
  final int recordSeconds;
  final double windowSeconds;
  final DateTime Function() _now;

  late final GalaxyCaptureLifecycle _lifecycle;
  final GalaxyBatchIngestor _batchIngestor = GalaxyBatchIngestor();
  final GalaxySignalPipeline _signalPipeline = GalaxySignalPipeline();

  final _stateCtrl = StreamController<GalaxyCaptureState>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _sub;
  Timer? _renderTimer;

  GalaxyCaptureState _state = GalaxyCaptureState.initial();
  double? _firstTimestampSec;
  double _lastTimestampSec = 0;

  Stream<GalaxyCaptureState> get state$ => _stateCtrl.stream;
  Stream<String> get errors$ => _errorCtrl.stream;

  void start() {
    _sub?.cancel();
    _lifecycle.reset();
    _signalPipeline.reset();
    _firstTimestampSec = null;
    _lastTimestampSec = 0;
    _state = GalaxyCaptureState.initial();

    _sub = _statusChannel.receiveBroadcastStream().listen(
      (event) => unawaited(_handleEvent(event)),
      onError: (error) => _errorCtrl.add('Error Data Layer: $error'),
    );

    _startRenderLoop();
    _stateCtrl.add(_state);
  }

  Future<void> dispose() async {
    _renderTimer?.cancel();
    await _sub?.cancel();
    await _lifecycle.abort();
    await _stateCtrl.close();
    await _errorCtrl.close();
  }

  Future<void> shareCsv() async {
    final path = await _lifecycle.commit();
    if (path == null) return;
    await Share.shareXFiles([XFile(path)], text: 'PPG CSV (Galaxy)');
  }

  Future<void> _handleEvent(dynamic event) async {
    if (event is! Map) return;

    final status = GalaxyWatchStatus.fromMap(Map<Object?, Object?>.from(event));
    final payload = status.payload;

    if (payload != null && payload.isNotEmpty) {
      final batch = parseGalaxyPayload(payload);
      if (batch != null) {
        await _ingestBatch(batch);
      }
    }

    _state = _state.copyWith(watchStatus: status);
    _stateCtrl.add(_state);
  }

  Future<void> _ingestBatch(GalaxyPayloadBatch batch) async {
    if (_lifecycle.captureCompleted) return;

    final normalized = _batchIngestor.normalize(
      incomingTimestamps: batch.timestampsSec,
      incomingValues: batch.values,
      firstTimestampSec: _firstTimestampSec,
      lastTimestampSec: _lastTimestampSec,
      windowSeconds: windowSeconds,
    );

    if (normalized == null) return;
    if (normalized.shouldResetChart) {
      _resetChart();
    }

    _lifecycle.markDataReceived();
    if (_lifecycle.shouldComplete()) {
      await _completeCapture();
      return;
    }

    _firstTimestampSec = normalized.firstTimestampSec;
    _lastTimestampSec = normalized.lastTimestampSec;

    _signalPipeline.enqueue(normalized.values);
    await _lifecycle.writeCsv(
      timestamps: normalized.timestamps,
      values: normalized.values,
    );

    _state = _state.copyWith(
      channelName: batch.channel,
      remainingSeconds: _lifecycle.getRemainingSeconds(),
    );
    _stateCtrl.add(_state);
  }

  void _startRenderLoop() {
    _renderTimer?.cancel();
    final intervalMs = (1000 / _renderFps).round();
    _renderTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _drainPendingSamplesForRendering();
    });
  }

  void _drainPendingSamplesForRendering() {
    if (!_signalPipeline.hasPendingSamples) return;

    _signalPipeline.drain(windowSeconds: windowSeconds);
    _state = _state.copyWith(
      spots: _signalPipeline.spots,
      minY: _signalPipeline.minY,
      maxY: _signalPipeline.maxY,
    );
    _stateCtrl.add(_state);
  }

  Future<void> _completeCapture() async {
    await _sub?.cancel();
    _sub = null;
    await _lifecycle.complete();
    _state = _state.copyWith(remainingSeconds: 0, completed: true);
    _stateCtrl.add(_state);
  }

  void _resetChart() {
    _signalPipeline.reset();
    _firstTimestampSec = null;
    _lastTimestampSec = 0;
    _state = _state.copyWith(spots: const []);
  }
}
