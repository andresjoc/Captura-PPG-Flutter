/// Infraestructura BLE de bajo nivel.
///
/// Aísla el plugin externo para evitar acoplar controladores/UI a detalles de
/// implementación y facilitar testing/migraciones futuras.

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Wrapper para BLE.
/// Centraliza el uso del plugin y facilita migrar a otro en el futuro.
class BleService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  Stream<DiscoveredDevice> scan() {
    // Escaneo amplio sin filtrar servicios para descubrir dispositivos cercanos.
    return _ble.scanForDevices(
      withServices: const [],
      scanMode: ScanMode.lowLatency,
    );
  }

  Stream<ConnectionStateUpdate> connect(String deviceId) {
    // Conexión con timeout explícito para evitar bloqueos indefinidos.
    return _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 12),
    );
  }

  Future<List<int>> readChar({
    required String deviceId,
    required Uuid serviceId,
    required Uuid characteristicId,
  }) async {
    // Lectura puntual (modo polling) de una característica BLE.
    final q = QualifiedCharacteristic(
      serviceId: serviceId,
      characteristicId: characteristicId,
      deviceId: deviceId,
    );
    return _ble.readCharacteristic(q);
  }

  /// Stream de NOTIFY / INDICATE para dispositivos que expongan data por suscripción.
  Stream<List<int>> subscribeChar({
    required String deviceId,
    required Uuid serviceId,
    required Uuid characteristicId,
  }) {
    final q = QualifiedCharacteristic(
      serviceId: serviceId,
      characteristicId: characteristicId,
      deviceId: deviceId,
    );
    return _ble.subscribeToCharacteristic(q);
  }
}
