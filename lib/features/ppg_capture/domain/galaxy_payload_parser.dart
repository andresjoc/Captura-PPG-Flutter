/// Normalizador de payloads heterogéneos de Galaxy Watch.
///
/// Convierte varios formatos de entrada en una forma única (timestamps + values)
/// para simplificar procesamiento, filtrado y render en tiempo real.

import 'dart:convert';

/// Lote normalizado de datos PPG provenientes de Galaxy Watch.
///
/// Independiza el resto del sistema del formato exacto del payload recibido.
class GalaxyPayloadBatch {
  GalaxyPayloadBatch({
    required this.channel,
    required this.timestampsSec,
    required this.values,
  });

  final String channel;
  final List<double> timestampsSec;
  final List<double> values;
}

/// Intenta convertir un payload heterogéneo a una estructura uniforme.
///
/// Soporta:
/// - JSON string,
/// - mapa con `samples`,
/// - formato tabular (`columns/index/data`),
/// - canales por clave (`GREEN`, `RED`, `IR`, `PPG`, con o sin `_DELTA`).
GalaxyPayloadBatch? parseGalaxyPayload(dynamic payload) {
  if (payload == null) return null;

  dynamic decoded = payload;
  if (payload is String) {
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return null;
    }
  }

  if (decoded is Map) {
    final map = decoded.cast<String, dynamic>();
    final raw = (map['raw'] is Map) ? map['raw'] as Map : map;
    final rawMap = raw.cast<String, dynamic>();

    final fromSamples = _parseSamples(rawMap);
    if (fromSamples != null) return fromSamples;

    final fromSplit = _parseSplit(rawMap);
    if (fromSplit != null) return fromSplit;

    final fromKeys = _parseKeyedChannels(rawMap);
    if (fromKeys != null) return fromKeys;
  }

  return null;
}

GalaxyPayloadBatch? _parseSamples(Map<String, dynamic> raw) {
  // Formato de lista simple: cada entrada puede ser [timestamp, valor] o valor.
  final samples = raw['samples'];
  if (samples is! List) return null;

  final timestamps = <double>[];
  final values = <double>[];
  for (final entry in samples) {
    if (entry is List && entry.length >= 2) {
      final ts = _normalizeTimestamp(entry[0]);
      final value = _toDouble(entry[1]);
      if (ts != null && value != null) {
        timestamps.add(ts);
        values.add(value);
      }
    } else {
      final value = _toDouble(entry);
      if (value != null) {
        timestamps.add(DateTime.now().millisecondsSinceEpoch / 1000.0);
        values.add(value);
      }
    }
  }

  if (values.isEmpty) return null;
  return GalaxyPayloadBatch(
    channel: 'PPG',
    timestampsSec: timestamps,
    values: values,
  );
}

GalaxyPayloadBatch? _parseSplit(Map<String, dynamic> raw) {
  // Formato tipo DataFrame serializado: columns + index + data por filas.
  if (raw['columns'] is! List || raw['index'] is! List || raw['data'] is! List) {
    return null;
  }

  final columns = (raw['columns'] as List).whereType<String>().toList();
  if (columns.isEmpty) return null;
  final index = raw['index'] as List;
  final data = raw['data'] as List;

  final preferred = _pickPreferredChannel(columns);
  final columnIndex = columns.indexOf(preferred);
  if (columnIndex < 0) return null;

  final timestamps = <double>[];
  final values = <double>[];

  for (var i = 0; i < data.length; i++) {
    final row = data[i];
    if (row is! List || row.length <= columnIndex) continue;
    final ts = _normalizeTimestamp(index[i]);
    final value = _toDouble(row[columnIndex]);
    if (ts != null && value != null) {
      timestamps.add(ts);
      values.add(value);
    }
  }

  if (values.isEmpty) return null;
  return GalaxyPayloadBatch(
    channel: preferred,
    timestampsSec: timestamps,
    values: values,
  );
}

GalaxyPayloadBatch? _parseKeyedChannels(Map<String, dynamic> raw) {
  // Formato por columnas sueltas, opcionalmente en deltas acumulables.
  const baseKeys = ['GREEN', 'RED', 'IR'];
  const timestampKey = 'TIMESTAMP';
  const deltaSuffix = '_DELTA';

  final availableKeys = raw.keys.map((k) => k.toUpperCase()).toSet();
  final isDelta = availableKeys.contains('$timestampKey$deltaSuffix');
  final actualTimestampKey = _findKey(raw, isDelta ? '$timestampKey$deltaSuffix' : timestampKey);
  if (actualTimestampKey == null) return null;

  String? channelKey;
  for (final key in baseKeys) {
    final candidate = isDelta ? '$key$deltaSuffix' : key;
    channelKey = _findKey(raw, candidate);
    if (channelKey != null) {
      break;
    }
  }
  channelKey ??= _findKey(raw, isDelta ? 'PPG$deltaSuffix' : 'PPG');
  if (channelKey == null) return null;

  final timestampsRaw = _extractNumList(raw[actualTimestampKey]);
  final valuesRaw = _extractNumList(raw[channelKey]);
  if (timestampsRaw.isEmpty || valuesRaw.isEmpty) return null;

  final timestamps = isDelta ? _deltasToValues(timestampsRaw) : timestampsRaw;
  final values = isDelta ? _deltasToValues(valuesRaw) : valuesRaw;

  final normalizedTimestamps = timestamps
      .map(_normalizeTimestamp)
      .whereType<double>()
      .toList();

  final normalizedValues =
      values.map(_toDouble).whereType<double>().toList();

  if (normalizedTimestamps.isEmpty || normalizedValues.isEmpty) {
    return null;
  }

  final length = normalizedTimestamps.length < normalizedValues.length
      ? normalizedTimestamps.length
      : normalizedValues.length;

  return GalaxyPayloadBatch(
    channel: channelKey.replaceAll(deltaSuffix, ''),
    timestampsSec: normalizedTimestamps.sublist(0, length),
    values: normalizedValues.sublist(0, length),
  );
}

List<double> _deltasToValues(List<double> deltas) {
  if (deltas.isEmpty) return deltas;
  final values = <double>[deltas.first];
  for (var i = 1; i < deltas.length; i++) {
    values.add(values.last + deltas[i]);
  }
  return values;
}

List<double> _extractNumList(dynamic value) {
  if (value is! List) return const [];
  return value.map(_toDouble).whereType<double>().toList();
}

String _pickPreferredChannel(List<String> columns) {
  const preferred = ['GREEN', 'PPG', 'RED', 'IR'];
  for (final key in preferred) {
    if (columns.contains(key)) return key;
    final match = columns.firstWhere(
      (c) => c.toUpperCase() == key,
      orElse: () => '',
    );
    if (match.isNotEmpty) return match;
  }
  return columns.first;
}

String? _findKey(Map<String, dynamic> raw, String target) {
  final upperTarget = target.toUpperCase();
  for (final key in raw.keys) {
    if (key.toUpperCase() == upperTarget) {
      return key;
    }
  }
  return null;
}

double? _normalizeTimestamp(dynamic value) {
  // Normaliza múltiples formatos de timestamp a segundos epoch (float).
  if (value == null) return null;
  if (value is num) {
    // Heurística de magnitud:
    // >1e11: milisegundos epoch modernos
    // >1e9 : segundos epoch
    // >1e6 : milisegundos en formatos abreviados
    if (value > 1e11) return value / 1000.0;
    if (value > 1e9) return value.toDouble();
    if (value > 1e6) return value / 1000.0;
    return value.toDouble();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.millisecondsSinceEpoch / 1000.0;
    final numeric = double.tryParse(value);
    if (numeric != null) return _normalizeTimestamp(numeric);
  }
  return null;
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
