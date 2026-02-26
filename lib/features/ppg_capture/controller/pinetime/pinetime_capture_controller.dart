/// Controlador de sesión PPG en tiempo real (PineTime).
///
/// Orquesta conexión BLE/estado y delega responsabilidades en componentes:
/// - salud de stream,
/// - pipeline de señal,
/// - lifecycle de captura/CSV,
/// - scheduler de render incremental.

import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/ble_service.dart';
import '../../data/csv_recorder.dart';
import '../../domain/ppg_aggregator.dart';
import '../../drivers/ppg_device_driver.dart';
import '../../models/capture_status.dart';
import 'pinetime_capture_lifecycle.dart';
import 'pinetime_render_scheduler.dart';
import 'realtime_signal_pipeline.dart';
import 'stream_health_monitor.dart';

class PinetimeCaptureController {
  final int pollMs;
  final int readTimeoutSeconds;
  final int recordSeconds;
  final int maxConsecutiveMisses;
  final int maxSameRaw;
  final int primeMaxTries;
  final int primeIntervalMs;
  final double dt;
  final double windowSeconds;
  final int renderFps;
  final DateTime Function() now;

  final BleService ble;
  final CsvRecorder recorder;
  final PpgDeviceDriver driver;
  final PpgAggregator? aggregator;

  PinetimeCaptureController({
    required this.ble,
    required this.recorder,
    required this.driver,
    this.aggregator,
    this.pollMs = 2000,
    this.readTimeoutSeconds = 3,
    this.recordSeconds = 90,
    this.maxConsecutiveMisses = 4,
    this.maxSameRaw = 3,
    this.primeMaxTries = 20,
    this.primeIntervalMs = 200,
    this.dt = 0.1,
    this.windowSeconds = 30,
    this.renderFps = 30,
    DateTime Function()? now,
  }) : assert(renderFps > 0, 'renderFps must be > 0'),
       now = now ?? DateTime.now {
    _signalPipeline = RealtimeSignalPipeline(
      dt: dt,
      windowSeconds: windowSeconds,
      lowCutHz: 0.5,
      highCutHz: 3.0,
    );
    _healthMonitor = StreamHealthMonitor(
      maxConsecutiveMisses: maxConsecutiveMisses,
      maxSameRaw: maxSameRaw,
    );
    _lifecycle = PinetimeCaptureLifecycle(
      recorder: recorder,
      now: this.now,
      recordSeconds: recordSeconds,
    );
    _renderScheduler = PinetimeRenderScheduler(dt: dt, renderFps: renderFps);
  }

  final _statusCtrl = StreamController<CaptureStatus>.broadcast();
  final _spotsCtrl = StreamController<List<FlSpot>>.broadcast();

  Stream<CaptureStatus> get status$ => _statusCtrl.stream;
  Stream<List<FlSpot>> get spots$ => _spotsCtrl.stream;

  CaptureStatus _status = CaptureStatus.initial(driverName: 'Unknown');

  String? _deviceId;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _rawSub;

  bool _running = false;
  Timer? _renderTimer;
  DateTime? _lastReadWall;
  DateTime? _lastValidWall;

  int _misses = 0;
  int _sameRaw = 0;
  late final StreamHealthMonitor _healthMonitor;
  late final RealtimeSignalPipeline _signalPipeline;
  late final PinetimeCaptureLifecycle _lifecycle;
  late final PinetimeRenderScheduler _renderScheduler;

  void _emitStatus(CaptureStatus s) {
    _status = s;
    _statusCtrl.add(_status);
  }

  void _emitSpots() {
    _spotsCtrl.add(_signalPipeline.spots);
  }

  void _emitOperationalStatus({
    required CapturePhase phase,
    String? error,
    int? remainingSeconds,
    String? csvPath,
  }) {
    _emitStatus(
      _status.copyWith(
        phase: phase,
        error: error,
        remainingSeconds: remainingSeconds,
        csvPath: csvPath,
        misses: _misses,
        sameRaw: _sameRaw,
        lastReadWall: _lastReadWall,
        lastValidWall: _lastValidWall,
      ),
    );
  }

  Future<void> start({required String deviceId}) async {
    _deviceId = deviceId;

    await _rawSub?.cancel();
    await _connSub?.cancel();

    _resetSession();

    _emitStatus(
      _status.copyWith(
        phase: CapturePhase.connecting,
        driverName: driver.name,
        error: null,
        csvPath: null,
      ),
    );

    _connSub = ble.connect(deviceId).listen(
      (u) async {
        if (u.connectionState == DeviceConnectionState.connected) {
          await _onConnected();
        } else if (u.connectionState == DeviceConnectionState.disconnected) {
          _running = false;
          await _rawSub?.cancel();
          _emitStatus(_status.copyWith(phase: CapturePhase.disconnected));
        }
      },
      onError: (e) {
        _emitStatus(
          _status.copyWith(phase: CapturePhase.error, error: 'Error conexión: $e'),
        );
      },
    );
  }

  Future<void> resync() async {
    _running = false;
    await _rawSub?.cancel();
    await _lifecycle.abort(deleteFile: true);

    _resetSession();

    if (_deviceId != null) {
      await _onConnected();
    }
  }

  Future<void> stop({bool abortAndDelete = true}) async {
    _running = false;
    _renderTimer?.cancel();
    await _rawSub?.cancel();
    await _connSub?.cancel();

    await _lifecycle.abort(deleteFile: abortAndDelete);

    _emitStatus(_status.copyWith(phase: CapturePhase.disconnected));
  }

  Future<void> shareCsvIfAvailable() async {
    final path = _lifecycle.csvPath;
    if (path == null) return;
    final f = File(path);
    if (!await f.exists()) return;

    await Share.shareXFiles([XFile(path)], text: 'PPG CSV');
  }

  Future<void> dispose() async {
    _running = false;
    _renderTimer?.cancel();
    await _rawSub?.cancel();
    await _connSub?.cancel();
    await _lifecycle.abort(deleteFile: false);

    await _statusCtrl.close();
    await _spotsCtrl.close();
  }

  void _resetSession() {
    _running = false;
    _renderTimer?.cancel();
    _renderScheduler.reset();
    _lastReadWall = null;
    _lastValidWall = null;

    _misses = 0;
    _sameRaw = 0;
    _healthMonitor.reset();

    _lifecycle.reset();
    _signalPipeline.reset(aggregator: aggregator);

    _status = CaptureStatus.initial(driverName: driver.name);
  }

  Future<void> _onConnected() async {
    _emitStatus(
      _status.copyWith(
        phase: CapturePhase.priming,
        error: null,
        lastReadWall: _lastReadWall,
        lastValidWall: _lastValidWall,
        misses: 0,
        sameRaw: 0,
      ),
    );

    final ok = await driver.prime(
      ble: ble,
      deviceId: _deviceId!,
      pollMs: pollMs,
      primeMaxTries: primeMaxTries,
      primeIntervalMs: primeIntervalMs,
      readOnceWithTimeout: _readOnceWithTimeout,
    );

    if (!ok) {
      _emitStatus(
        _status.copyWith(
          phase: CapturePhase.error,
          error:
              'No fue posible enganchar el stream. Verifica el sensor y usa Re-sincronizar.',
          lastReadWall: _lastReadWall,
          lastValidWall: _lastValidWall,
        ),
      );
      return;
    }

    _emitStatus(
      _status.copyWith(
        phase: CapturePhase.waitingFirstData,
        error: null,
        lastReadWall: _lastReadWall,
        lastValidWall: _lastValidWall,
      ),
    );

    _startRawStream();
  }

  Future<List<int>> _readOnceWithTimeout() async {
    final raw = await Future.any([
      ble.readChar(
        deviceId: _deviceId!,
        serviceId: driver.serviceUuid,
        characteristicId: driver.characteristicUuid,
      ),
      if (!driver.usesNotify)
        Future<List<int>>.delayed(
          Duration(seconds: readTimeoutSeconds),
          () => throw TimeoutException('BLE read timeout (${readTimeoutSeconds}s)'),
        ),
    ]);
    _lastReadWall = now();
    return raw;
  }

  void _startRawStream() async {
    await _rawSub?.cancel();
    _running = true;

    final raw$ = driver.rawStream(ble: ble, deviceId: _deviceId!, pollMs: pollMs);

    _startRenderLoop();

    _rawSub = raw$.listen(
      (raw) async {
        await _handleRaw(raw);
      },
      onError: (e) async {
        _healthMonitor.registerStreamError();
        _syncHealthMetrics();
        if (_lifecycle.firstValidWall != null && _healthMonitor.reachedMissLimit) {
          await _abortWithError('No está llegando info (errores/misses=$_misses).');
        } else {
          _emitStatus(
            _status.copyWith(
              phase: _status.phase == CapturePhase.disconnected
                  ? CapturePhase.error
                  : _status.phase,
              error: 'Error stream: $e',
              misses: _misses,
              sameRaw: _sameRaw,
              lastReadWall: _lastReadWall,
              lastValidWall: _lastValidWall,
            ),
          );
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _handleRaw(List<int> raw) async {
    if (!_running) return;

    _lastReadWall = now();

    final assessment = _healthMonitor.assessRaw(
      raw: raw,
      minPayloadBytes: driver.minPayloadBytes,
    );
    _syncHealthMetrics();

    if (assessment == RawPacketAssessment.invalidPayload) {
      if (_lifecycle.firstValidWall != null && _healthMonitor.reachedMissLimit) {
        await _abortWithError('No está llegando info (misses=$_misses).');
      }
      return;
    }

    _lastValidWall = now();

    if (assessment == RawPacketAssessment.repeatedPayload) {
      await _abortWithError('Stream pegado (paquete repetido). Usa Re-sincronizar.');
      return;
    }

    if (_lifecycle.firstValidWall == null) {
      await _lifecycle.startRecordingIfNeeded(prefix: 'ppg');
      _emitOperationalStatus(
        phase: CapturePhase.recording,
        error: null,
        remainingSeconds: recordSeconds,
      );
    }

    if (_lifecycle.shouldComplete()) {
      await _completeAndCommit();
      return;
    }

    _emitOperationalStatus(
      phase: CapturePhase.recording,
      error: null,
      remainingSeconds: _lifecycle.remainingSeconds(),
    );

    final decodedSamples = driver.decodeSamples(raw);
    final newSegment = _signalPipeline.extractNewSegment(
      driver: driver,
      aggregator: aggregator,
      decodedSamples: decodedSamples,
    );
    if (newSegment.isEmpty) return;

    await _lifecycle.writeSegment(dt: dt, values: newSegment);

    _renderScheduler.enqueueAll(newSegment);
  }

  void _startRenderLoop() {
    _renderTimer?.cancel();
    _renderScheduler.reset();
    final intervalMs = (1000 / renderFps).round();
    _renderTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _drainPendingRenderSamples();
    });
  }

  void _drainPendingRenderSamples() {
    if (!_renderScheduler.hasPendingSamples) return;
    final segment = _renderScheduler.takeNextTickSegment();
    if (segment.isEmpty) return;
    _signalPipeline.appendSegment(segment);
    _emitSpots();
  }

  Future<void> _completeAndCommit() async {
    _running = false;
    _renderTimer?.cancel();
    await _rawSub?.cancel();

    final csvPath = await _lifecycle.commit();

    _emitOperationalStatus(
      phase: CapturePhase.completed,
      error: null,
      remainingSeconds: 0,
      csvPath: csvPath,
    );
  }

  Future<void> _abortWithError(String reason) async {
    _running = false;
    _renderTimer?.cancel();
    await _rawSub?.cancel();
    await _lifecycle.abort(deleteFile: true);

    _emitOperationalStatus(phase: CapturePhase.error, error: reason, csvPath: null);
  }

  void _syncHealthMetrics() {
    _misses = _healthMonitor.misses;
    _sameRaw = _healthMonitor.sameRaw;
  }
}
