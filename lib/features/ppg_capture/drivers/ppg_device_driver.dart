/// Contrato de driver para dispositivos PPG.
///
/// Permite soportar relojes distintos con la misma orquestación del controller,
/// cambiando únicamente adaptación de transporte y formato de payload.

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../data/ble_service.dart';

/// Driver genérico para un dispositivo PPG.
///
/// Objetivo:
/// - encapsular "cómo obtener data":
///   - READ polling vs NOTIFY subscription
/// - encapsular "cómo decodificar":
///   - bytes → samples
/// - encapsular si necesita o no agregación (buffers solapados).
///
/// El controller usa un driver para no acoplarse a un reloj específico.
abstract class PpgDeviceDriver {
  /// Nombre del driver (útil para UI/logs).
  String get name;

  /// Servicio BLE donde vive la señal PPG.
  Uuid get serviceUuid;

  /// Característica BLE que entrega data.
  Uuid get characteristicUuid;

  /// Tamaño mínimo esperado del payload (en bytes).
  /// Ej: PineTime raw = 128 bytes.
  int get minPayloadBytes;

  /// Si true, el driver usa NOTIFY (subscribe) en vez de READ.
  bool get usesNotify;

  /// Decodifica bytes crudos a una lista de samples enteros.
  /// Ej: PineTime = 64 uint16 LE.
  List<int> decodeSamples(List<int> raw);

  /// Indica si los samples vienen en buffers solapados que requieren agregación.
  bool get needsAggregation;

  /// Indica si conviene ignorar cola final (safetyTail) por estabilidad.
  /// Para dispositivos sin agregación, típicamente es 0.
  int get safetyTail;

  /// Implementación del stream de bytes crudos.
  ///
  /// - Para READ: un loop que lee y hace delay.
  /// - Para NOTIFY: `ble.subscribeChar(...)`.
  Stream<List<int>> rawStream({
    required BleService ble,
    required String deviceId,
    required int pollMs,
  });

  /// Priming opcional:
  /// - Por defecto: intenta ver que el payload cambia entre lecturas.
  /// - Para NOTIFY: puede bastar recibir dos paquetes distintos.
  ///
  /// Retorna true si el stream parece “vivo”.
  Future<bool> prime({
    required BleService ble,
    required String deviceId,
    required int pollMs,
    required int primeMaxTries,
    required int primeIntervalMs,
    required Future<List<int>> Function() readOnceWithTimeout,
  });
}
