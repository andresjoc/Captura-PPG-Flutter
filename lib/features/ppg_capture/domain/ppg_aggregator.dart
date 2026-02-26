/// Algoritmo de agregación para buffers PPG solapados.
///
/// Algunos dispositivos entregan bloques con datos repetidos entre lecturas;
/// este módulo elimina duplicados y reconstruye una serie continua.

int _min(int a, int b) => a < b ? a : b;

/// Resultado del cálculo de solape.
class OverlapResult {
  final int? index;
  final int overlappedSize;
  OverlapResult(this.index, this.overlappedSize);
}

/// Traducción directa del algoritmo original en Python.
///
/// Busca el desplazamiento `i` con mayor coincidencia entre:
/// - `arr1[i:]` (cola del buffer anterior)
/// - `arr2[:-i]` (inicio del buffer nuevo)
///
/// Ese `i` permite estimar cuánto solape existe entre buffers consecutivos.
OverlapResult mostOverlapIndex(List<int> arr1, List<int> arr2) {
  int? ind;
  var overlappedSize = 20;

  final n = _min(arr1.length, arr2.length);
  final half = (n / 2).floor();

  for (var i = 1; i < half; i++) {
    final len = n - i;
    var zerosCount = 0;
    for (var k = 0; k < len; k++) {
      if (arr1[i + k] == arr2[k]) zerosCount++;
    }
    if (overlappedSize < zerosCount) {
      ind = i;
      overlappedSize = zerosCount;
    }
  }
  return OverlapResult(ind, overlappedSize);
}

/// Traducción de `diffSubsetRange` del código Python.
///
/// Compara dos buffers posición a posición e identifica el rango de cambios,
/// ignorando los últimos 4 elementos por margen de seguridad.
({int start, int end}) diffSubsetRange(List<int> arr1, List<int> arr2) {
  final n = _min(arr1.length, arr2.length);
  final safeN = (n - 4) < 0 ? 0 : (n - 4);

  int? start;
  int? end;

  for (var i = 0; i < safeN; i++) {
    if (arr1[i] != arr2[i]) {
      start ??= i;
      end = i;
    }
  }

  if (start == null || end == null) return (start: 0, end: -1);
  return (start: start, end: end);
}

/// Traducción de `add_new_data` del flujo Python.
///
/// Regla general:
/// - si se detecta solape confiable, recorta la cola inconsistente previa y agrega
///   solo muestras nuevas,
/// - si no hay solape claro, agrega únicamente el rango con diferencias detectadas.
List<int> addNewData(List<int> aggregatedData, List<int> arr1, List<int> arr2) {
  final r = mostOverlapIndex(arr1, arr2);
  final ind = r.index;
  final zeros = r.overlappedSize;

  if (ind != null && ind != 0) {
    // 64 corresponde al tamaño fijo del bloque PineTime (64 muestras por lectura).
    // El recorte evita duplicar cola al reconstruir la serie continua.
    final badEndingCount = -(64 - ind - zeros);

    final aggregatorStriped =
        (badEndingCount < 0 && (aggregatedData.length + badEndingCount) >= 0)
        ? aggregatedData.sublist(0, aggregatedData.length + badEndingCount)
        : aggregatedData;

    final newValues = arr2.sublist(arr2.length - ind);
    return [...aggregatorStriped, ...newValues];
  } else {
    final range = diffSubsetRange(arr1, arr2);
    if (range.end < range.start) return aggregatedData;
    final newValues = arr2.sublist(range.start, range.end + 1);
    return [...aggregatedData, ...newValues];
  }
}

/// Agregador para dispositivos que entregan buffers con solape (ring-buffer).
///
/// Mantiene internamente el último buffer recibido para deduplicar muestras
/// cuando llega el siguiente bloque.
class PpgAggregator {
  List<int>? _last;
  List<int> aggregated = [];

  List<int> push(List<int> buffer) {
    if (_last == null) {
      _last = buffer;
      aggregated = [...buffer];
      return aggregated;
    }
    final arr1 = _last!;
    final arr2 = buffer;
    _last = arr2;

    aggregated = addNewData(aggregated, arr1, arr2);
    return aggregated;
  }

  void reset() {
    _last = null;
    aggregated = [];
  }
}
