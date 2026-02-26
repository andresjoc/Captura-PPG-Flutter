/// Pantalla de selección de origen de captura.
///
/// ## Responsabilidad de UI
/// Este widget funciona como menú de navegación y **no ejecuta lógica de
/// negocio**: no conecta BLE, no parsea datos y no escribe CSV.
///
/// Solo decide qué flujo abrir:
/// - PineTime (BLE).
/// - Galaxy (Data Layer).

import 'package:flutter/material.dart';

import 'galaxy_ppg_page.dart';
import 'scan_page.dart';

class DeviceSelectPage extends StatelessWidget {
  const DeviceSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Menú de entrada por tipo de integración/dispositivo.
    return Scaffold(
      appBar: AppBar(title: const Text('Seleccionar dispositivo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('PineTime (BLE)'),
              subtitle: const Text('Escanear dispositivos BLE disponibles.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScanPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Galaxy Watch (Data Layer)'),
              subtitle: const Text(
                'Conexión vía Data Layer API sin escaneo BLE.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GalaxyPpgPage()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
