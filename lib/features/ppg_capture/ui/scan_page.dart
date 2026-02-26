/// UI de escaneo BLE y selección de dispositivo.
///
/// ## Principio de diseño
/// Esta pantalla se limita a UX de descubrimiento:
/// - permisos,
/// - listado de dispositivos,
/// - navegación a la pantalla de captura.
///
/// La captura real NO se realiza aquí. Una vez seleccionado el dispositivo,
/// la lógica pasa a `PpgPage`, que a su vez consume `PineCaptureApi`.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ble_service.dart';
import 'ppg_page.dart';

/// UI demo: escanear BLE y abrir la pantalla de captura.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  static const _savedPineTimeIdKey = 'saved_pinetime_device_id';
  static const _savedPineTimeNameKey = 'saved_pinetime_device_name';

  // Servicio BLE para discovery; no administra sesión de captura.
  final BleService ble = BleService();
  StreamSubscription<DiscoveredDevice>? _sub;

  final Map<String, DiscoveredDevice> _devices = {};
  bool scanning = false;
  bool _showOnlyInfiniTime = true;
  String? _savedDeviceId;
  String? _savedDeviceName;

  @override
  void initState() {
    super.initState();
    _loadSavedDevice();
    _requestPermsThenScan();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Recupera último dispositivo usado para reconexión rápida desde la UI.
  Future<void> _loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_savedPineTimeIdKey);
    final savedName = prefs.getString(_savedPineTimeNameKey);

    if (!mounted) return;
    setState(() {
      _savedDeviceId = savedId;
      _savedDeviceName = savedName;
    });
  }

  // Persistencia mínima de selección de reloj para ahorrar pasos al usuario.
  Future<void> _saveDevice(DiscoveredDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedPineTimeIdKey, device.id);
    await prefs.setString(_savedPineTimeNameKey, device.name);

    if (!mounted) return;
    setState(() {
      _savedDeviceId = device.id;
      _savedDeviceName = device.name;
    });
  }

  bool _isPineTime(DiscoveredDevice d) {
    return d.name.trim() == 'InfiniTime';
  }

  bool _matchesCurrentFilter(DiscoveredDevice d) {
    return !_showOnlyInfiniTime || _isPineTime(d);
  }

  Future<void> _requestPermsThenScan() async {
    final sdkInt = await _readAndroidSdkInt();

    // Android 12+ (API 31+): BLE moderno (scan/connect) sin forzar ubicación.
    // Android <= 11: permisos legacy BLE + ubicación para discovery.
    final requiredPermissions = <Permission>[
      if (sdkInt != null && sdkInt >= 31) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ] else if (sdkInt != null && sdkInt <= 30) ...[
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ],
    ];

    if (requiredPermissions.isEmpty) {
      await _startScan();
      return;
    }

    final statuses = await requiredPermissions.request();
    final denied = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList();

    if (denied.isNotEmpty) {
      final blocked = statuses.values.any((status) => status.isPermanentlyDenied);
      final deniedLabel = denied.map(_permissionLabel).join(', ');
      final reason = blocked
          ? 'Concede los permisos en Ajustes para continuar.'
          : 'Debes concederlos para escanear dispositivos BLE.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Permisos críticos no concedidos: $deniedLabel. $reason',
            ),
          ),
        );
      }
      return;
    }

    await _startScan();
  }

  Future<int?> _readAndroidSdkInt() async {
    if (!Platform.isAndroid) return null;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt;
  }

  String _permissionLabel(Permission permission) {
    return switch (permission) {
      Permission.bluetoothScan => 'bluetoothScan',
      Permission.bluetoothConnect => 'bluetoothConnect',
      Permission.bluetooth => 'bluetooth',
      Permission.locationWhenInUse => 'locationWhenInUse',
      _ => permission.toString(),
    };
  }

  Future<void> _startScan() async {
    // Reinicia catálogo local para evitar mezclar resultados viejos.
    await _sub?.cancel();
    setState(() {
      scanning = true;
      _devices.clear();
    });

    _sub = ble.scan().listen(
      (d) {
        setState(() => _devices[d.id] = d);
      },
      onError: (e) {
        setState(() => scanning = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error escaneando: $e')));
      },
    );

    // Timeout defensivo: evita escaneo infinito por consumo de batería/UX.
    Future.delayed(const Duration(seconds: 10), () async {
      if (!mounted) return;
      await _sub?.cancel();
      setState(() => scanning = false);
    });
  }

  // Navegación al flujo de captura PineTime con el dispositivo elegido.
  // Aquí solo se enruta: la lógica de sesión vive en API/controller.
  Future<void> _openPpgFromDevice(DiscoveredDevice device) async {
    await _saveDevice(device);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PpgPage(device: device)),
    );
  }

  // Reconstruye un dispositivo "ligero" desde storage para abrir captura directa.
  Future<void> _connectSavedDevice() async {
    if (_savedDeviceId == null) return;

    final saved = DiscoveredDevice(
      id: _savedDeviceId!,
      name: _savedDeviceName ?? 'InfiniTime',
      serviceData: const {},
      manufacturerData: Uint8List(0),
      rssi: 0,
      serviceUuids: const [],
      connectable: Connectable.available,
    );

    await _openPpgFromDevice(saved);
  }

  @override
  Widget build(BuildContext context) {
    // Lista visible ordenada por potencia de señal para priorizar cercanos.
    final list = _devices.values.where(_matchesCurrentFilter).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear BLE'),
        actions: [
          IconButton(
            tooltip: _showOnlyInfiniTime
                ? 'Mostrar todos los dispositivos'
                : 'Mostrar solo InfiniTime',
            onPressed: () {
              setState(() => _showOnlyInfiniTime = !_showOnlyInfiniTime);
            },
            icon: Icon(
              _showOnlyInfiniTime ? Icons.filter_alt : Icons.filter_alt_off,
            ),
          ),
          IconButton(
            onPressed: scanning ? null : _startScan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: list.length + (_savedDeviceId != null ? 2 : 1),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            return ListTile(
              title: Text(scanning ? 'Escaneando…' : 'Escaneo detenido'),
              subtitle: Text(
                _showOnlyInfiniTime
                    ? '${list.length} dispositivos InfiniTime detectados'
                    : '${list.length} dispositivos detectados',
              ),
            );
          }

          if (_savedDeviceId != null && i == 1) {
            final savedName = (_savedDeviceName?.isNotEmpty ?? false)
                ? _savedDeviceName!
                : 'InfiniTime';

            return ListTile(
              leading: const Icon(Icons.watch),
              title: Text(savedName),
              subtitle: Text('Guardado: $_savedDeviceId'),
              trailing: const Icon(Icons.link),
              onTap: _connectSavedDevice,
            );
          }

          final offset = _savedDeviceId != null ? 2 : 1;
          final d = list[i - offset];
          final name = d.name.isNotEmpty ? d.name : '(sin nombre)';

          return ListTile(
            title: Text(name),
            subtitle: Text('id: ${d.id} • RSSI: ${d.rssi}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPpgFromDevice(d),
          );
        },
      ),
    );
  }
}
