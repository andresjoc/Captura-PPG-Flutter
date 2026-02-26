/// Punto de compatibilidad para imports legacy.
///
/// Este archivo reexporta el servicio BLE real para mantener estabilidad de
/// rutas mientras la arquitectura evoluciona.

/// Compatibilidad temporal:
///
/// Mantener este archivo evita romper imports históricos.
/// El servicio BLE oficial vive en:
/// `lib/features/ppg_capture/data/ble_service.dart`.
export '../features/ppg_capture/data/ble_service.dart';
