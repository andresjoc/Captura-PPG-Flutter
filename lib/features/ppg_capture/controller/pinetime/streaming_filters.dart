/// Utilidades de filtrado causal para procesamiento PPG en tiempo real.
///
/// Este archivo separa la matemática de DSP del controller principal:
/// - el controller orquesta la sesión (BLE, estado, CSV),
/// - estas clases procesan la señal muestra a muestra.
///
/// La separación mejora mantenibilidad y facilita pruebas aisladas de filtros.

import 'dart:math' as math;

/// Bloqueador DC (high-pass suave de primer orden).
///
/// Ayuda a remover deriva lenta de baseline antes del band-pass principal.
class DcBlocker {
  final double _a;

  double _x1 = 0.0;
  double _y1 = 0.0;

  DcBlocker({required double fs, required double cutoffHz})
    : _a = (() {
        final dt = 1.0 / fs;
        final rc = 1.0 / (2.0 * math.pi * cutoffHz);
        return rc / (rc + dt);
      })();

  /// Procesa una muestra en modo causal (solo usa estado pasado).
  double step(double x) {
    final y = _a * (_y1 + x - _x1);
    _x1 = x;
    _y1 = y;
    return y;
  }
}

/// Band-pass causal aproximado Butterworth orden 5 en cascada:
/// (2º + 2º + 1º) high-pass y luego low-pass.
class StreamingBandpassFilter {
  final BiquadStateful _hp1;
  final BiquadStateful _hp2;
  final FirstOrderStateful _hp3;

  final BiquadStateful _lp1;
  final BiquadStateful _lp2;
  final FirstOrderStateful _lp3;

  StreamingBandpassFilter({
    required double fs,
    required double lowcutHz,
    required double highcutHz,
  }) : _hp1 = BiquadStateful.highpass(
         fs: fs,
         f0: lowcutHz,
         q: 0.6180339887498948,
       ),
       _hp2 = BiquadStateful.highpass(
         fs: fs,
         f0: lowcutHz,
         q: 1.618033988749895,
       ),
       _hp3 = FirstOrderStateful.highpass(fs: fs, f0: lowcutHz),
       _lp1 = BiquadStateful.lowpass(
         fs: fs,
         f0: highcutHz,
         q: 0.6180339887498948,
       ),
       _lp2 = BiquadStateful.lowpass(
         fs: fs,
         f0: highcutHz,
         q: 1.618033988749895,
       ),
       _lp3 = FirstOrderStateful.lowpass(fs: fs, f0: highcutHz);

  /// Aplica la cascada completa a una muestra.
  ///
  /// Orden del pipeline:
  /// 1) tres etapas high-pass (remueven componente lenta),
  /// 2) tres etapas low-pass (recortan alta frecuencia y ruido).
  ///
  /// Es un filtro causal: no usa muestras futuras, ideal para tiempo real.
  double step(double x) {
    var y = x;

    y = _hp1.step(y);
    y = _hp2.step(y);
    y = _hp3.step(y);

    y = _lp1.step(y);
    y = _lp2.step(y);
    y = _lp3.step(y);

    return y;
  }
}

/// Biquad con estado (Direct Form I) para operación sample-by-sample.
class BiquadStateful {
  final double b0, b1, b2, a1, a2;

  double _x1 = 0.0, _x2 = 0.0, _y1 = 0.0, _y2 = 0.0;

  BiquadStateful._({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  factory BiquadStateful.lowpass({
    required double fs,
    required double f0,
    required double q,
  }) {
    final w0 = 2 * math.pi * f0 / fs;
    final c = math.cos(w0);
    final s = math.sin(w0);
    final alpha = s / (2 * q);

    double b0 = (1 - c) / 2;
    double b1 = 1 - c;
    double b2 = (1 - c) / 2;
    double a0 = 1 + alpha;
    double a1 = -2 * c;
    double a2 = 1 - alpha;

    b0 /= a0;
    b1 /= a0;
    b2 /= a0;
    a1 /= a0;
    a2 /= a0;

    return BiquadStateful._(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2);
  }

  factory BiquadStateful.highpass({
    required double fs,
    required double f0,
    required double q,
  }) {
    final w0 = 2 * math.pi * f0 / fs;
    final c = math.cos(w0);
    final s = math.sin(w0);
    final alpha = s / (2 * q);

    double b0 = (1 + c) / 2;
    double b1 = -(1 + c);
    double b2 = (1 + c) / 2;
    double a0 = 1 + alpha;
    double a1 = -2 * c;
    double a2 = 1 - alpha;

    b0 /= a0;
    b1 /= a0;
    b2 /= a0;
    a1 /= a0;
    a2 /= a0;

    return BiquadStateful._(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2);
  }

  double step(double x) {
    // Ecuación diferencia (Direct Form I):
    // y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
    // Luego se desplazan los estados para el siguiente sample.
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;

    _x2 = _x1;
    _x1 = x;

    _y2 = _y1;
    _y1 = y;

    return y;
  }
}

/// Filtro de primer orden con estado para completar la aproximación orden 5.
class FirstOrderStateful {
  final double b0, b1, a1;

  double _x1 = 0.0;
  double _y1 = 0.0;

  FirstOrderStateful._({required this.b0, required this.b1, required this.a1});

  factory FirstOrderStateful.lowpass({
    required double fs,
    required double f0,
  }) {
    final k = math.tan(math.pi * f0 / fs);
    final b0 = k / (1 + k);
    final b1 = b0;
    final a1 = (k - 1) / (k + 1);
    return FirstOrderStateful._(b0: b0, b1: b1, a1: a1);
  }

  factory FirstOrderStateful.highpass({
    required double fs,
    required double f0,
  }) {
    final k = math.tan(math.pi * f0 / fs);
    final b0 = 1 / (1 + k);
    final b1 = -b0;
    final a1 = (k - 1) / (k + 1);
    return FirstOrderStateful._(b0: b0, b1: b1, a1: a1);
  }

  double step(double x) {
    // Ecuación de 1er orden con estado interno (causal).
    final y = b0 * x + b1 * _x1 - a1 * _y1;
    _x1 = x;
    _y1 = y;
    return y;
  }
}
