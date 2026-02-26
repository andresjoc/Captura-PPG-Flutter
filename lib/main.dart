/// Punto de entrada de la app Flutter de captura PPG.
///
/// La app está organizada para que la capa visual no implemente lógica técnica
/// de conexión BLE, parseo de payloads o filtrado de señal; esa lógica vive en
/// capas internas reutilizables.

import 'package:flutter/material.dart';
import 'features/ppg_capture/ui/device_select_page.dart';

/// Entry-point de la app.
///
/// Esta app demuestra arquitectura por capas:
/// UI -> API de captura -> Controller/Domain/Data.
void main() {
  runApp(const MyApp());
}

/// App raíz con Material 3.
///
/// Solo define navegación inicial; no contiene lógica de negocio.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PPG Capture',
      theme: ThemeData(useMaterial3: true),
      home: const DeviceSelectPage(),
    );
  }
}
