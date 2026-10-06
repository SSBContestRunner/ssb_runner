import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/training/session_random.dart';

/// Builds the exchange an *incoming* station transmits, given its callsign.
/// Per-contest implementations live at the bottom of this file.
typedef ReceivedExchange =
    String Function({
      required SessionRandom random,
      required String callerCallsign,
      required DxccManager dxccManager,
    });

/// US / Canada DXCC entity ids (cty `adif`).
const Set<int> wveDxccIds = {291, 1};

bool isWveDxcc(int dxccId) => wveDxccIds.contains(dxccId);

/// ARRL DX multipliers for W/VE stations: the 48 contiguous US states plus DC.
/// Alaska (KL7) and Hawaii (KH6) are DXCC entities and send power instead.
const List<String> arrlUsStates = [
  'AL', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'DC', 'FL', 'GA', 'ID', 'IL',
  'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO',
  'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR',
  'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI',
  'WY',
];

/// Canadian provinces / territories (ARRL list; VO1/VO2 counted separately).
const List<String> arrlCanadaProvinces = [
  'AB', 'BC', 'LB', 'MB', 'NB', 'NF', 'NS', 'NT', 'NU', 'ON', 'PE', 'QC',
  'SK', 'YT',
];

/// US call-area digit -> candidate states (ARRL DX multiplier set).
const Map<String, List<String>> _usAreaStates = {
  '0': ['CO', 'IA', 'KS', 'MN', 'MO', 'ND', 'NE', 'SD'],
  '1': ['CT', 'ME', 'MA', 'NH', 'RI', 'VT'],
  '2': ['NJ', 'NY'],
  '3': ['DE', 'DC', 'MD', 'PA'],
  '4': ['AL', 'FL', 'GA', 'KY', 'NC', 'SC', 'TN', 'VA'],
  '5': ['AR', 'LA', 'MS', 'NM', 'OK', 'TX'],
  '6': ['CA'],
  '7': ['AZ', 'ID', 'MT', 'NV', 'OR', 'UT', 'WA', 'WY'],
  '8': ['MI', 'OH', 'WV'],
  '9': ['IL', 'IN', 'WI'],
};

/// Canadian VE digit -> candidate provinces / territories.
const Map<String, List<String>> _veAreaProvinces = {
  '1': ['NS', 'NB', 'PE'],
  '2': ['QC'],
  '3': ['ON'],
  '4': ['MB'],
  '5': ['SK'],
  '6': ['AB'],
  '7': ['BC'],
  '8': ['NT', 'NU'],
  '9': ['NB'],
};

/// JIDX prefecture numbers by JA call area (jidxmult.lst).
const Map<String, List<int>> jidxAreaPrefectures = {
  '0': [8, 9],
  '1': [10, 11, 12, 13, 14, 15, 16, 17],
  '2': [18, 19, 20, 21],
  '3': [22, 23, 24, 25, 26, 27],
  '4': [31, 32, 33, 34, 35],
  '5': [36, 37, 38, 39],
  '6': [40, 41, 42, 43, 44, 45, 46, 47],
  '7': [2, 3, 4, 5, 6, 7],
  '8': [1],
  '9': [28, 29, 30],
};

/// US call-area digit -> ITU zone, from ARRL's published US ITU zone borders.
/// cty only carries the US entity default (ITU 8), which is wrong for the
/// western call areas (6) and the central ones (7).
const Map<String, int> _usAreaItuZones = {
  '0': 7,
  '1': 8,
  '2': 8,
  '3': 8,
  '4': 8,
  '5': 7,
  '6': 6,
  '7': 6,
  '8': 8,
  '9': 8,
};

const List<int> _jidxJd1Prefectures = [48, 49, 50];

/// Plausible ARRL DX power values for DX stations.
const List<String> arrlPowerValues = [
  '100',
  '200',
  '400',
  '500',
  '1000',
  '1500',
];

/// JA prefecture numbers the given callsign's call area can report. Falls back
/// to the full 01..50 set when the callsign does not encode a JA call area.
List<int> jidxPrefecturesFor(String callsign) {
  final call = callsign.toUpperCase();
  if (call.startsWith('JD1')) return _jidxJd1Prefectures;
  final digit = _firstDigit(call);
  return jidxAreaPrefectures[digit] ??
      List<int>.generate(50, (index) => index + 1);
}

int _pick(SessionRandom random, int length) {
  assert(length > 0);
  return random.nextExchange(length) - 1;
}

String? _firstDigit(String callsign) =>
    RegExp(r'[0-9]').firstMatch(callsign)?.group(0);

/// CQ zone of the caller, or a random 1..[fallbackMax] when unknown.
String _cqZoneExchange(
  SessionRandom random,
  String callerCallsign,
  DxccManager dxccManager, {
  int fallbackMax = 40,
}) =>
    dxccManager.findCallsignCqZone(callerCallsign)?.toString() ??
    random.nextExchange(fallbackMax).toString();

String _canadaProvince(SessionRandom random, String callsign) {
  final call = callsign.toUpperCase();
  if (call.startsWith('VO1')) return 'NF';
  if (call.startsWith('VO2')) return 'LB';
  if (call.startsWith('VY1')) return 'YT';
  if (call.startsWith('VY2')) return 'PE';
  if (call.startsWith('VY0')) return 'NU';
  final provinces = _veAreaProvinces[_firstDigit(call)];
  if (provinces != null) return provinces[_pick(random, provinces.length)];
  return arrlCanadaProvinces[_pick(random, arrlCanadaProvinces.length)];
}

/// CQ WW: the caller's CQ zone.
String receivedCqZone({
  required SessionRandom random,
  required String callerCallsign,
  required DxccManager dxccManager,
}) => _cqZoneExchange(random, callerCallsign, dxccManager);

/// IARU HF: the caller's ITU zone (US calls refined by call area).
String receivedItuZone({
  required SessionRandom random,
  required String callerCallsign,
  required DxccManager dxccManager,
}) {
  final call = callerCallsign.toUpperCase();
  if (dxccManager.findCallsignDxccId(call) == 291) {
    final zone = _usAreaItuZones[_firstDigit(call)];
    if (zone != null) return zone.toString();
  }
  return dxccManager.findCallsignItuZone(call)?.toString() ??
      random.nextExchange(90).toString();
}

/// JIDX: JA callers send a prefecture in their call area, others a CQ zone.
String receivedJidx({
  required SessionRandom random,
  required String callerCallsign,
  required DxccManager dxccManager,
}) {
  final dxccId = dxccManager.findCallsignDxccId(callerCallsign);
  if (isJapanDxcc(dxccId)) {
    final prefectures = jidxPrefecturesFor(callerCallsign);
    return prefectures[_pick(random, prefectures.length)].toString();
  }
  return _cqZoneExchange(random, callerCallsign, dxccManager);
}

/// ARRL DX: W/VE callers send a state/province, DX callers send power.
String receivedArrlDx({
  required SessionRandom random,
  required String callerCallsign,
  required DxccManager dxccManager,
}) {
  final dxccId = dxccManager.findCallsignDxccId(callerCallsign);
  if (dxccId == 291) {
    final states =
        _usAreaStates[_firstDigit(callerCallsign.toUpperCase())] ??
        arrlUsStates;
    return states[_pick(random, states.length)];
  }
  if (dxccId == 1) {
    return _canadaProvince(random, callerCallsign);
  }
  return arrlPowerValues[_pick(random, arrlPowerValues.length)];
}