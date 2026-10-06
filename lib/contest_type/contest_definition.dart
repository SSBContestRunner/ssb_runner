import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx.dart';
import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/training/session_random.dart';

/// Metadata and factory for one contest.  The selector consumes this registry;
/// contest code is never selected by a UI string or a hard-coded `if` chain.
abstract class ContestDefinition {
  const ContestDefinition();
  String get id;
  String get name;
  String get exchangeLabel;
  String get scoringNotice;

  /// Declares which station-configured fields the operator's exchange needs,
  /// resolved for the given station callsign (ARRL/JIDX switch on DXCC).
  MyExchangePlan myExchangePlan({
    required String stationCallsign,
    required DxccManager dxccManager,
  });

  ContestType create({
    required String stationCallsign,
    required DxccManager dxccManager,
    required StationExchangeConfig stationExchange,
  });
}

class ContestRegistry {
  static const all = <ContestDefinition>[
    CqWpxDefinition(),
    CqWwSsbDefinition(),
    ArrlDxDefinition(),
    IaruHfDefinition(),
    JidxSsbDefinition(),
  ];

  static ContestDefinition byId(String? id) => all.firstWhere(
    (definition) => definition.id == id,
    orElse: () => all.first,
  );
}

StationExchangeField _cqZoneField() => StationExchangeField(
  id: 'cqZone',
  label: 'CQ Zone',
  min: 1,
  max: 40,
  audioDigits: 2,
  derive: (stationCallsign, dxccManager) =>
      dxccManager.findCallsignCqZone(stationCallsign)?.toString(),
);

class CqWpxDefinition extends ContestDefinition {
  const CqWpxDefinition();
  @override
  String get id => 'CQ-WPX';
  @override
  String get name => 'CQ WPX';
  @override
  String get exchangeLabel => '59 #';
  @override
  String get scoringNotice => 'Single-band training score; prefix multipliers.';

  @override
  MyExchangePlan myExchangePlan({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) => const MyExchangePlan(fields: [], sendsSerial: true, serialDigits: 3);

  @override
  ContestType create({
    required String stationCallsign,
    required DxccManager dxccManager,
    required StationExchangeConfig stationExchange,
  }) => CqWpxContestType(
    stationCallsign: stationCallsign,
    dxccManager: dxccManager,
    stationExchange: stationExchange,
  );
}

class CqWwSsbDefinition extends _NumericContestDefinition {
  const CqWwSsbDefinition();
  @override
  String get id => 'CQ-WW-SSB';
  @override
  String get name => 'CQ WW';
  @override
  String get exchangeLabel => '59 Zone';
  @override
  int get maxExchange => 40;
  @override
  int get exchangeAudioDigits => 2;
  @override
  String get scoringNotice =>
      'Single-band training score; DXCC and zone multipliers.';

  @override
  MyExchangePlan myExchangePlan({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) => MyExchangePlan(fields: [_cqZoneField()], sendsSerial: false);

  @override
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station) {
    if (dxcc.findCallsignDxccId(qso.callsign) ==
        dxcc.findCallsignDxccId(station)) {
      return 0;
    }
    return dxcc.findCallSignContinent(qso.callsign) ==
            dxcc.findCallSignContinent(station)
        ? 1
        : 3;
  }
}

class ArrlDxDefinition extends _NumericContestDefinition {
  const ArrlDxDefinition();
  @override
  String get id => 'ARRL-DX';
  @override
  String get name => 'ARRL DX';
  @override
  String get exchangeLabel => '59 Power';
  @override
  int get maxExchange => 1500;
  @override
  int get exchangeAudioDigits => 0;
  @override
  String get scoringNotice =>
      'Training profile; validate station category before official scoring.';

  @override
  MyExchangePlan myExchangePlan({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) => MyExchangePlan(
    fields: [
      StationExchangeField(
        id: 'power',
        label: 'Power',
        min: 1,
        max: 1500,
        audioDigits: 0,
        helperText: 'Transmitter output in watts',
      ),
    ],
    sendsSerial: false,
  );

  @override
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station) => 3;
}

class IaruHfDefinition extends _NumericContestDefinition {
  const IaruHfDefinition();
  @override
  String get id => 'IARU-HF';
  @override
  String get name => 'IARU HF';
  @override
  String get exchangeLabel => '59 ITU Zone';
  @override
  int get maxExchange => 90;
  @override
  int get exchangeAudioDigits => 2;
  @override
  String get scoringNotice =>
      'Single-band training score; country and zone multipliers.';

  @override
  MyExchangePlan myExchangePlan({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) => MyExchangePlan(
    fields: [
      StationExchangeField(
        id: 'ituZone',
        label: 'ITU Zone',
        min: 1,
        max: 90,
        audioDigits: 2,
        derive: (stationCallsign, dxccManager) =>
            dxccManager.findCallsignItuZone(stationCallsign)?.toString(),
      ),
    ],
    sendsSerial: false,
  );

  @override
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station) =>
      dxcc.findCallSignContinent(qso.callsign) ==
          dxcc.findCallSignContinent(station)
      ? 1
      : 3;
}

class JidxSsbDefinition extends _NumericContestDefinition {
  const JidxSsbDefinition();
  @override
  String get id => 'JIDX-SSB';
  @override
  String get name => 'JIDX';
  @override
  String get exchangeLabel => '59 Prefecture / CQ Zone';
  @override
  int get maxExchange => 50;
  @override
  int get exchangeAudioDigits => 2;
  @override
  String get scoringNotice =>
      'Training profile; Japanese-prefecture exchange practice.';

  @override
  MyExchangePlan myExchangePlan({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) {
    // JA stations send a prefecture number (01-50); everyone else sends the
    // station's CQ zone. JIDX has no serial exchange (design 13.2).
    if (isJapanDxcc(dxccManager.findCallsignDxccId(stationCallsign))) {
      return MyExchangePlan(
        fields: [
          StationExchangeField(
            id: 'prefecture',
            label: 'Prefecture',
            min: 1,
            max: 50,
            audioDigits: 2,
          ),
        ],
        sendsSerial: false,
      );
    }
    return MyExchangePlan(fields: [_cqZoneField()], sendsSerial: false);
  }

  @override
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station) => 1;
}

abstract class _NumericContestDefinition extends ContestDefinition {
  const _NumericContestDefinition();
  int get maxExchange;
  int get exchangeAudioDigits;
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station);

  @override
  ContestType create({
    required String stationCallsign,
    required DxccManager dxccManager,
    required StationExchangeConfig stationExchange,
  }) => _NumericContestType(
    maxExchange: maxExchange,
    exchangeAudioDigits: exchangeAudioDigits,
    plan: myExchangePlan(
      stationCallsign: stationCallsign,
      dxccManager: dxccManager,
    ),
    stationExchange: stationExchange,
    stationCallsign: stationCallsign,
    dxccManager: dxccManager,
    pointsFor: pointsFor,
  );
}

class _NumericContestType implements ContestType {
  _NumericContestType({
    required int maxExchange,
    required int exchangeAudioDigits,
    required MyExchangePlan plan,
    required StationExchangeConfig stationExchange,
    required String stationCallsign,
    required DxccManager dxccManager,
    required _PointsFor pointsFor,
  }) : _exchangeManager = _NumericExchangeManager(maxExchange),
       _scoreCalculator = _NumericScoreCalculator(
         stationCallsign,
         dxccManager,
         pointsFor,
       ),
       _builder = StationExchangeBuilder(
         plan: plan,
         config: stationExchange,
         stationCallsign: stationCallsign,
         dxccManager: dxccManager,
         exchangeAudioDigits: exchangeAudioDigits,
       );

  final _NumericExchangeManager _exchangeManager;
  final _NumericScoreCalculator _scoreCalculator;
  final StationExchangeBuilder _builder;

  @override
  RegExp get allowExchangeRegex => RegExp('[0-9]');
  @override
  _NumericExchangeManager get exchangeManager => _exchangeManager;
  @override
  _NumericScoreCalculator get scoreCalculator => _scoreCalculator;
  @override
  String buildMyExchange(int qsoNumber) => _builder.buildMyExchange(qsoNumber);
  @override
  String formatExchangeForAudio(String exchange) =>
      _builder.formatExchangeForAudio(exchange);
}

class _NumericExchangeManager implements ExchangeManager {
  _NumericExchangeManager(this.max);
  final int max;
  @override
  String generateExchange(SessionRandom random) =>
      random.nextExchange(max).toString();
  @override
  String processExchange(String exchange) =>
      exchange.replaceFirst(RegExp(r'^0+(?=.)'), '');
}

typedef _PointsFor =
    int Function(QsoTableData qso, DxccManager dxcc, String station);

class _NumericScoreCalculator implements ScoreCalculator {
  _NumericScoreCalculator(
    this.stationCallsign,
    this.dxccManager,
    this._pointsFor,
  );
  @override
  final String stationCallsign;
  final DxccManager dxccManager;
  final _PointsFor _pointsFor;

  @override
  CorrectnessType calculateCorrectness(QsoTableData qso) =>
      qso.callsign == qso.callsignCorrect && qso.exchange == qso.exchangeCorrect
      ? Correct()
      : Incorrect();

  @override
  ScoreData calculateScore(List<QsoTableData> qsos) {
    final multipliers = <String>{};
    var points = 0;
    for (final qso in qsos) {
      points += _pointsFor(qso, dxccManager, stationCallsign);
      multipliers
        ..add('dxcc-${dxccManager.findCallsignDxccId(qso.callsign)}')
        ..add('exchange-${qso.exchangeCorrect}');
    }
    return ScoreData(
      count: qsos.length,
      multiple: multipliers.length,
      score: points * multipliers.length,
    );
  }
}
