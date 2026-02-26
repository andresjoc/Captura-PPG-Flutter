/// Filtros de señal reutilizables para procesamiento PPG.
///
/// Implementa band-pass zero-phase (offline/ventana) con padding reflectivo y
/// cascada de biquads; útil para suavizar baseline y ruido fuera de banda.

import 'dart:math' as math;

class SignalFilter {
  static const List<double> _qValues = [0.541196100146197, 1.3065629648763766];

  static List<double> applyZeroPhaseBandpass(
    List<double> input, {
    required double fs,
    required double lowcutHz,
    required double highcutHz,
  }) {
    final n = input.length;
    if (n < 3) {
      return List<double>.from(input);
    }

    final padLength = math.max(1, math.min(12, n - 2));
    final padded = _reflectPad(input, padLength);

    // Primer pase (forward): aplica la respuesta del filtro en avance temporal.
    var filtered = _applyForward(
      padded,
      fs: fs,
      lowcutHz: lowcutHz,
      highcutHz: highcutHz,
    );

    // Segundo pase (backward): reduce desfase de fase aparente en visualización.
    filtered = filtered.reversed.toList(growable: false);
    filtered = _applyForward(
      filtered,
      fs: fs,
      lowcutHz: lowcutHz,
      highcutHz: highcutHz,
    );
    filtered = filtered.reversed.toList(growable: false);

    return filtered.sublist(padLength, padLength + n);
  }

  static List<double> _reflectPad(List<double> input, int padLength) {
    // Padding reflectivo: disminuye artefactos de borde al filtrar ventanas cortas.
    final n = input.length;
    final left = List<double>.generate(
      padLength,
      (i) => 2 * input.first - input[i + 1],
      growable: false,
    );
    final right = List<double>.generate(
      padLength,
      (i) => 2 * input.last - input[n - 2 - i],
      growable: false,
    );
    return [...left, ...input, ...right];
  }

  static List<double> _applyForward(
    List<double> input, {
    required double fs,
    required double lowcutHz,
    required double highcutHz,
  }) {
    var y = List<double>.from(input, growable: false);
    for (final q in _qValues) {
      y = _highpassBiquad(fs, lowcutHz, q).filter(y);
    }
    for (final q in _qValues) {
      y = _lowpassBiquad(fs, highcutHz, q).filter(y);
    }
    return y;
  }

  static _BiquadSection _lowpassBiquad(double fs, double f0, double q) {
    final w0 = 2 * math.pi * f0 / fs;
    final c = math.cos(w0);
    final s = math.sin(w0);
    final alpha = s / (2 * q);
    final b0 = (1 - c) / 2;
    final b1 = 1 - c;
    final b2 = (1 - c) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * c;
    final a2 = 1 - alpha;
    return _BiquadSection(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }

  static _BiquadSection _highpassBiquad(double fs, double f0, double q) {
    final w0 = 2 * math.pi * f0 / fs;
    final c = math.cos(w0);
    final s = math.sin(w0);
    final alpha = s / (2 * q);
    final b0 = (1 + c) / 2;
    final b1 = -(1 + c);
    final b2 = (1 + c) / 2;
    final a0 = 1 + alpha;
    final a1 = -2 * c;
    final a2 = 1 - alpha;
    return _BiquadSection(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }
}

class _BiquadSection {
  const _BiquadSection({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  List<double> filter(List<double> x) {
    final y = List<double>.filled(x.length, 0.0, growable: false);
    var x1 = 0.0;
    var x2 = 0.0;
    var y1 = 0.0;
    var y2 = 0.0;
    for (var i = 0; i < x.length; i++) {
      final out = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      y[i] = out;
      x2 = x1;
      x1 = x[i];
      y2 = y1;
      y1 = out;
    }
    return y;
  }
}
