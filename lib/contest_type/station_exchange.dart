import 'package:ssb_runner/dxcc/dxcc_manager.dart';

/// DXCC entity ids that JIDX treats as "JA" (Japan, Ogasawara, Minami Torishima).
const Set<int> japanDxccIds = {339, 192, 177};

bool isJapanDxcc(int dxccId) => japanDxccIds.contains(dxccId);

/// One station-configured component of the operator's own (sent) exchange.
class StationExchangeField {
  const StationExchangeField({
    required this.id,
    required this.label,
    this.numeric = true,
    this.min,
    this.max,
    this.audioDigits = 0,
    this.helperText,
    this.derive,
    this.validator,
  });

  /// Stable persistence key, e.g. `cqZone` / `ituZone` / `power` / `prefecture`.
  final String id;

  /// UI label, e.g. `CQ Zone`.
  final String label;
  final bool numeric;
  final int? min;
  final int? max;

  /// Leading-zero width used when reading the value over the air.
  /// 0 = read as entered; 2 = CQ/ITU zone and JIDX prefecture; 3 = serial.
  final int audioDigits;
  final String? helperText;

  /// Optional default derived from the station callsign + DXCC data.
  final String? Function(String stationCallsign, DxccManager dxccManager)?
  derive;

  /// Optional extra validation for non-numeric fields.
  final bool Function(String value)? validator;
}

/// Declarative description of what the operator's station sends for a contest,
/// resolved for a specific station callsign (ARRL/JIDX switch on DXCC).
class MyExchangePlan {
  const MyExchangePlan({
    required this.fields,
    required this.sendsSerial,
    this.serialDigits = 3,
  });

  final List<StationExchangeField> fields;

  /// True when the contest sends a running serial (only CQ WPX today).
  final bool sendsSerial;
  final int serialDigits;
}

/// Per-contest station exchange values, persisted explicitly by the operator.
/// Derived defaults are deliberately not persisted (see design 3.3).
class StationExchangeConfig {
  const StationExchangeConfig(this.values);

  static const empty = StationExchangeConfig({});

  final Map<String, String> values;

  String? operator [](String id) => values[id];

  StationExchangeConfig withValue(String id, String? value) {
    final updated = Map<String, String>.from(values);
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      updated.remove(id);
    } else {
      updated[id] = trimmed;
    }
    return StationExchangeConfig(updated);
  }

  Map<String, Object> toJson() => {'values': values};

  factory StationExchangeConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['values'];
    final map = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is String) map[key] = value;
      });
    }
    return StationExchangeConfig(map);
  }
}

/// Explicit configuration wins; otherwise fall back to the derived default.
String? resolveExchangeValue(
  StationExchangeField field,
  StationExchangeConfig config,
  String stationCallsign,
  DxccManager dxccManager,
) {
  final explicit = config[field.id]?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  return field.derive?.call(stationCallsign, dxccManager);
}

/// Strips leading zeros and pads to [digits] (digits <= 0 keeps the value).
String formatExchangeNumber(String value, int digits) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final stripped = trimmed.replaceFirst(RegExp(r'^0+(?=.)'), '');
  if (digits <= 0 || stripped.length >= digits) return stripped;
  return stripped.padLeft(digits, '0');
}

/// Returns an English error when a required plan field is missing or invalid.
String? validateStationExchange({
  required MyExchangePlan plan,
  required StationExchangeConfig config,
  required String stationCallsign,
  required DxccManager dxccManager,
}) {
  if (plan.sendsSerial) return null;
  for (final field in plan.fields) {
    final value = resolveExchangeValue(
      field,
      config,
      stationCallsign,
      dxccManager,
    );
    if (value == null || value.isEmpty) return 'Please set ${field.label}';
    if (field.numeric) {
      final parsed = int.tryParse(value);
      if (parsed == null) return 'Please enter a valid ${field.label}';
      if (field.min != null && parsed < field.min!) {
        return '${field.label} must be between ${field.min} and ${field.max}';
      }
      if (field.max != null && parsed > field.max!) {
        return '${field.label} must be between ${field.min} and ${field.max}';
      }
    } else if (field.validator != null && !field.validator!(value)) {
      return 'Please enter a valid ${field.label}';
    }
  }
  return null;
}

/// Builds the operator's own exchange and normalises the received exchange for
/// over-the-air playback (per-contest leading-zero policy).
class StationExchangeBuilder {
  const StationExchangeBuilder({
    required this.plan,
    required this.config,
    required this.stationCallsign,
    required this.dxccManager,
    required this.exchangeAudioDigits,
  });

  final MyExchangePlan plan;
  final StationExchangeConfig config;
  final String stationCallsign;
  final DxccManager dxccManager;

  /// Digits used when reading the *received* exchange over the air.
  final int exchangeAudioDigits;

  /// The exchange the operator transmits for the 1-based [qsoNumber].
  String buildMyExchange(int qsoNumber) {
    if (plan.sendsSerial) {
      return formatExchangeNumber(qsoNumber.toString(), plan.serialDigits);
    }
    final parts = <String>[];
    for (final field in plan.fields) {
      final value = resolveExchangeValue(
        field,
        config,
        stationCallsign,
        dxccManager,
      );
      if (value == null || value.isEmpty) continue;
      parts.add(
        field.numeric ? formatExchangeNumber(value, field.audioDigits) : value,
      );
    }
    return parts.join(' ');
  }

  /// Received exchange -> spoken form. Letters pass through untouched.
  String formatExchangeForAudio(String exchange) {
    final trimmed = exchange.trim();
    if (trimmed.isEmpty) return trimmed;
    final isNumeric = trimmed.codeUnits.every(
      (unit) => unit >= 0x30 && unit <= 0x39,
    );
    if (!isNumeric) return trimmed;
    return formatExchangeNumber(trimmed, exchangeAudioDigits);
  }
}
