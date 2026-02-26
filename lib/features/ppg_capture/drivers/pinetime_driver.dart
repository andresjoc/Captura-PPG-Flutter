/// Driver concreto para PineTime/InfiniTime.
///
/// Define UUIDs, estrategia de lectura (polling READ), priming y decodificación
/// específica del dispositivo para desacoplar el controller del hardware.

import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../data/ble_service.dart';
import '../domain/bytes_equal.dart';
import '../domain/ppg_decoder.dart';

import 'ppg_device_driver.dart';

/// Driver para PineTime / InfiniTime:
/// - usa READ (no notify)
/// - characteristic 2A39 (raw buffer)
/// - payload 128 bytes = 64 uint16 LE
/// - requiere agregación (buffers solapados)
class PineTimeDriver implements PpgDeviceDriver {
  @override
  String get name => 'PineTime (InfiniTime)';

  @override
  Uuid get serviceUuid => Uuid.parse("0000180e-0000-1000-8000-00805f9b34fb");

  @override
  Uuid get characteristicUuid =>
      Uuid.parse("00002a39-0000-1000-8000-00805f9b34fb");

  @override
  int get minPayloadBytes => 128;

  @override
  bool get usesNotify => false;

  @override
  bool get needsAggregation => true;

  @override
  int get safetyTail => 10;

  @override
  List<int> decodeSamples(List<int> raw) => decode64U16LE(raw);

  @override
  Stream<List<int>> rawStream({
    required BleService ble,
    required String deviceId,
    required int pollMs,
  }) async* {
    // Polling secuencial: una lectura por iteración y pausa controlada.
    while (true) {
      final raw = await ble.readChar(
        deviceId: deviceId,
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
      );
      yield raw;
      await Future.delayed(Duration(milliseconds: pollMs));
    }
  }

  @override
  Future<bool> prime({
    required BleService ble,
    required String deviceId,
    required int pollMs,
    required int primeMaxTries,
    required int primeIntervalMs,
    required Future<List<int>> Function() readOnceWithTimeout,
  }) async {
    // Priming: verifica que el buffer realmente esté avanzando en el tiempo.
    List<int>? prevRaw;

    for (var i = 0; i < primeMaxTries; i++) {
      try {
        final raw = await readOnceWithTimeout();
        if (raw.length < minPayloadBytes) {
          await Future.delayed(Duration(milliseconds: primeIntervalMs));
          continue;
        }

        if (prevRaw == null) {
          prevRaw = raw;
          await Future.delayed(Duration(milliseconds: primeIntervalMs));
          continue;
        }

        if (!bytesEqual(prevRaw, raw)) return true;
        await Future.delayed(Duration(milliseconds: primeIntervalMs));
      } catch (_) {
        await Future.delayed(Duration(milliseconds: primeIntervalMs));
      }
    }
    return false;
  }
}
