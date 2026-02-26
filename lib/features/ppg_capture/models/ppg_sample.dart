/// Modelo de muestra PPG simple (tiempo + valor).
///
/// Sirve como contrato semántico para representar puntos de señal cruda.

/// Representa una muestra PPG (cruda).
///
/// Nota:
/// - `t` se construye internamente usando un `dt` aproximado (ej. 50 ms).
/// - `value` es un entero (uint16 decodificado).
class PpgSample {
  /// Tiempo “de señal” en segundos (no necesariamente timestamp real del sensor).
  final double t;

  /// Valor crudo del PPG (uint16).
  final int value;

  const PpgSample({required this.t, required this.value});
}
