# 📡 PPG Capture Platform (Flutter)

Aplicación Flutter para adquisición, visualización y exportación de señal PPG desde relojes inteligentes, diseñada con **arquitectura por capas** y separación estricta entre UI, orquestación de captura, dominio de señal y persistencia.

> Objetivo del diseño: facilitar mantenimiento, trazabilidad clínica/técnica de la señal y extensión a nuevos dispositivos sin degradar la base existente.

---

## Tabla de contenido

1. [Propósito del sistema](#propósito-del-sistema)
2. [Decisiones de arquitectura](#decisiones-de-arquitectura)
3. [Visión por capas](#visión-por-capas)
4. [Estructura del proyecto y rol de carpetas](#estructura-del-proyecto-y-rol-de-carpetas)
5. [Flujos funcionales](#flujos-funcionales)
6. [Documentación detallada de `lib/features`](#documentación-detallada-de-libfeatures)
7. [Gestión de calidad de señal](#gestión-de-calidad-de-señal)
8. [Persistencia CSV y consistencia](#persistencia-csv-y-consistencia)
9. [Configuración clave](#configuración-clave)
10. [Extensibilidad](#extensibilidad)
11. [Ejecución local](#ejecución-local)
12. [Permisos Android](#permisos-android)
13. [Troubleshooting](#troubleshooting)

---

## Propósito del sistema

El proyecto captura PPG en tiempo real y ofrece:

- **Visualización continua** en ventana deslizante.
- **Persistencia segura** a CSV.
- **Control de sesión temporal** (90s por defecto) para uniformidad de datasets.
- **Exportación compartible** del archivo generado.

Soporta dos estrategias de origen:

1. **PineTime por BLE directo**.
2. **Galaxy Watch por Data Layer / EventChannel**.

---

## Decisiones de arquitectura

### ¿Por qué está dividido así?

Se divide para reducir acoplamiento y aislar cambios por naturaleza técnica:

- **UI** cambia por experiencia de usuario.
- **Controller/API** cambia por reglas de sesión y coordinación.
- **Domain** cambia por reglas matemáticas/parseo de señal.
- **Data/Drivers** cambia por protocolos físicos (BLE, canales nativos, archivos).

Esta segmentación permite:

- Sustituir o agregar relojes sin reescribir la UI.
- Cambiar filtros/decoders sin tocar flujo visual.
- Auditar errores de captura por capas (conectividad vs. parseo vs. render).

---

## Visión por capas

```text
UI (pantallas Flutter)
   ↓
API (fachadas para frontend)
   ↓
Controller (orquestación de sesión + estado)
   ↓
Domain (parseo/filtrado/transformaciones puras)
   ↓
Drivers + Data (BLE/EventChannel/CSV)
```

### Principio rector

La UI **no** implementa lógica de señal ni persistencia: solo consume estado y dispara acciones.

### Contrato UI ↔ API (principio clave)

- Las pantallas en `ui/` **no** contienen lógica de captura, parseo, filtros ni persistencia.
- Cada pantalla consume una API (`PineCaptureApi` o `GalaxyCaptureApi`) y se limita a:
  - escuchar streams de estado/serie,
  - renderizar componentes visuales,
  - disparar comandos de alto nivel (`start`, `resync`, `share`, `dispose`).
- Las APIs delegan en controller/domain/data para centralizar reglas operativas y mantener widgets predecibles.


---

## Estructura del proyecto y rol de carpetas

```text
lib/
  main.dart                       # Entrypoint Flutter y bootstrap
  ble/                            # Compatibilidad/re-export legacy
  features/                       # Dominio funcional principal
    ppg_capture/
      api/                        # Fachadas consumidas por UI
      controller/                 # Orquestación de captura y lifecycle
      data/                       # Persistencia y acceso a servicios de datos
      domain/                     # Reglas puras de señal y parseo
      drivers/                    # Contratos/adaptadores de dispositivo
      models/                     # Estados y DTOs tipados
      ui/                         # Pantallas y widgets de flujo
```

---

## Flujos funcionales

## 1) PineTime (BLE)

Pipeline lógico:

`PpgPage → PineCaptureApi → PinetimeCaptureController → PineTimeDriver/BleService + RealtimeSignalPipeline + CsvRecorder`

Pasos:

1. UI inicia sesión con `start(deviceId)`.
2. Controller conecta y ejecuta priming del dispositivo.
3. Al validar datos: abre CSV temporal, procesa señal, publica spots y escribe muestras.
4. Monitoriza salud del stream (misses/repetidos).
5. Al cumplir tiempo: commit de CSV y estado `completed`.
6. Si hay error: abort y limpieza segura.

## 2) Galaxy Watch (Data Layer)

Pipeline lógico:

`GalaxyPpgPage → GalaxyCaptureApi → GalaxyCaptureController → EventChannel + Parser + SignalPipeline + CsvRecorder`

Pasos:

1. UI inicia escucha de `ppg_events`.
2. Se parsea payload por batch.
3. Se normalizan timestamps, se deduplica y se drena al pipeline visual.
4. Se escribe CSV durante la sesión.
5. Al cumplir tiempo: commit, estado final y cierre de stream.

---

## Documentación detallada de `lib/features`

A continuación se describe la función de cada sección dentro de `features/ppg_capture`.

### `api/`

- **`pine_capture_api.dart`**: fachada para UI PineTime. Expone streams de estado/serie y comandos de sesión.
- **`galaxy_capture_api.dart`**: fachada equivalente para Galaxy, desacoplando EventChannel y lógica interna de la vista.

### `controller/`

#### `controller/pinetime/`

- **`pinetime_capture_controller.dart`**: orquestador principal de sesión PineTime (conexión, priming, stream, render, lifecycle).
- **`pinetime_capture_lifecycle.dart`**: reglas de inicio real, conteo temporal, commit/abort de CSV.
- **`pinetime_render_scheduler.dart`**: control de presupuesto de muestras por tick para render estable.
- **`realtime_signal_pipeline.dart`**: procesamiento causal para gráfica de baja latencia.
- **`stream_health_monitor.dart`**: detección de payload inválido, repetición excesiva y misses.
- **`streaming_filters.dart`**: filtros de soporte para tratamiento de señal en streaming.

#### `controller/galaxy/`

- **`galaxy_capture_controller.dart`**: coordinador de sesión Galaxy y publicación de `GalaxyCaptureState`.
- **`galaxy_capture_lifecycle.dart`**: control temporal + persistencia de sesión Galaxy.
- **`galaxy_batch_ingestor.dart`**: normalización de lotes entrantes (dedupe, recorte por ventana, reset por salto temporal).
- **`galaxy_signal_pipeline.dart`**: pipeline visual para filtrado/ventana/rango Y estable.

### `data/`

- **`ble_service.dart`**: encapsula operaciones BLE concretas.
- **`csv_recorder.dart`**: escritura transaccional (`.tmp.csv` → commit final `.csv`).

### `domain/`

- **`ppg_decoder.dart`**: decodifica payloads crudos a muestras significativas.
- **`ppg_aggregator.dart`**: agregación/normalización de muestras cuando aplica.
- **`galaxy_payload_parser.dart`**: parseo de payload Galaxy a lotes tipados.
- **`signal_filter.dart`**: filtros de señal y utilidades DSP.
- **`bytes_equal.dart`**: utilidad de comparación eficiente de payload binario.

### `drivers/`

- **`ppg_device_driver.dart`**: contrato base para drivers de captura.
- **`pinetime_driver.dart`**: implementación concreta para PineTime (UUID, priming, lectura).

### `models/`

- **`capture_status.dart`**: estado de sesión PineTime.
- **`ppg_sample.dart`**: muestra PPG tipada.
- **`galaxy_watch_status.dart`**: estado del reloj/evento Galaxy.
- **`galaxy_capture_state.dart`**: estado agregado expuesto a UI Galaxy.

### `ui/`

- **`device_select_page.dart`**: acceso inicial a flujos de captura.
- **`scan_page.dart`**: descubrimiento BLE y navegación por dispositivo.
- **`ppg_page.dart`**: pantalla de sesión PineTime.
- **`galaxy_ppg_page.dart`**: pantalla de sesión Galaxy.

---

## Gestión de calidad de señal

- **PineTime:** enfoque causal para baja latencia y continuidad de render.
- **Galaxy:** drenado incremental + estabilización de rango Y para suavidad visual.

Se separa explícitamente calidad de stream (controller) de calidad de señal (domain/pipeline).

---

## Persistencia CSV y consistencia

`CsvRecorder` usa estrategia segura:

1. Inicio en archivo temporal.
2. Escritura incremental por segmentos/lotes.
3. Commit atómico al completar.
4. Abort con limpieza en caso de error.

Con esto se evitan archivos incompletos en cortes de sesión.

---

## Configuración clave

### PineTime

- `pollMs`
- `readTimeoutSeconds`
- `recordSeconds`
- `maxConsecutiveMisses`
- `maxSameRaw`
- `primeMaxTries`
- `primeIntervalMs`
- `dt`
- `windowSeconds`
- `renderFps`
- `now` (inyectable)

### Galaxy

- `recordSeconds`
- `windowSeconds`
- `now` (inyectable)

---

## Extensibilidad

### Nuevo reloj BLE

1. Implementar `PpgDeviceDriver`.
2. Definir UUIDs y estrategia de lectura/notificación.
3. Conectar en API/controller correspondiente.

### Nuevo origen tipo Data Layer

1. Crear API/controller análogo a Galaxy.
2. Mantener parseo/filtros/CSV en backend de feature.
3. Exponer a UI solo streams/comandos de alto nivel.

---

## Ejecución local

```bash
flutter pub get
flutter run
```

---

## Permisos Android

Resumen de runtime en flujo BLE:

| Android | Permisos principales |
|---|---|
| 12+ (API 31+) | `bluetoothScan`, `bluetoothConnect` |
| <= 11 (API <= 30) | `bluetooth`, `locationWhenInUse` |

---

## Troubleshooting

- **Paquetes repetidos o stream degradado (Pine):** usar resync y revisar proximidad/dispositivo.
- **CSV no visible:** solo aparece tras commit de sesión.
- **Galaxy sin datos:** validar emisión del canal `ppg_events` del lado nativo.

---

## Licencia

Pendiente de definición.
