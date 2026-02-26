/// Decoder de bajo nivel para bloques crudos PineTime.
///
/// Traduce bytes little-endian a muestras numéricas para las capas superiores.

/// Decodifica 128 bytes como 64 uint16 little-endian.
/// Equivalente a Python: struct.unpack('<64H', raw)
List<int> decode64U16LE(List<int> raw) {
  final out = List<int>.filled(64, 0);
  for (var i = 0; i < 64; i++) {
    final lo = raw[i * 2];
    final hi = raw[i * 2 + 1];
    out[i] = (hi << 8) | lo;
  }
  return out;
}
