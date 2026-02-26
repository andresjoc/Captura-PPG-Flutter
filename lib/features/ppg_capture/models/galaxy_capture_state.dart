/// Estado inmutable expuesto por el flujo de captura Galaxy.
///
/// La UI consume este modelo para renderizar estado operativo, serie de puntos
/// para gráfica y metadatos de progreso sin acoplarse a la lógica interna.
import 'package:fl_chart/fl_chart.dart';

import 'galaxy_watch_status.dart';

class GalaxyCaptureState {
  const GalaxyCaptureState({
    required this.watchStatus,
    required this.channelName,
    required this.spots,
    required this.minY,
    required this.maxY,
    required this.remainingSeconds,
    required this.completed,
  });

  factory GalaxyCaptureState.initial() => const GalaxyCaptureState(
    watchStatus: GalaxyWatchStatus.initial(),
    channelName: 'PPG',
    spots: <FlSpot>[],
    minY: -100,
    maxY: 100,
    remainingSeconds: null,
    completed: false,
  );

  final GalaxyWatchStatus watchStatus;
  final String channelName;
  final List<FlSpot> spots;
  final double minY;
  final double maxY;
  final int? remainingSeconds;
  final bool completed;

  GalaxyCaptureState copyWith({
    GalaxyWatchStatus? watchStatus,
    String? channelName,
    List<FlSpot>? spots,
    double? minY,
    double? maxY,
    int? remainingSeconds,
    bool? completed,
  }) {
    return GalaxyCaptureState(
      watchStatus: watchStatus ?? this.watchStatus,
      channelName: channelName ?? this.channelName,
      spots: spots ?? this.spots,
      minY: minY ?? this.minY,
      maxY: maxY ?? this.maxY,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      completed: completed ?? this.completed,
    );
  }
}
