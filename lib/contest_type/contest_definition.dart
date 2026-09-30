import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx.dart';
import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
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
  ContestType create({
    required String stationCallsign,
    required DxccManager dxccManager,
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

class CqWpxDefinition extends ContestDefinition {
  const CqWpxDefinition();
  @override
  String get id => 'CQ-WPX';
  @override
  String get name => 'CQ WPX SSB';
  @override
  String get exchangeLabel => '59 #';
  @override
  String get scoringNotice => 'Single-band training score; prefix multipliers.';
  @override
  ContestType create({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) => CqWpxContestType(
    stationCallsign: stationCallsign,
    dxccManager: dxccManager,
  );
}

class CqWwSsbDefinition extends _NumericContestDefinition {
  const CqWwSsbDefinition();
  @override
  String get id => 'CQ-WW-SSB';
  @override
  String get name => 'CQ WW SSB';
  @override
  String get exchangeLabel => '59 Zone';
  @override
  int get maxExchange => 40;
  @override
  String get scoringNotice =>
      'Single-band training score; DXCC and zone multipliers.';
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
  String get name => 'ARRL DX SSB';
  @override
  String get exchangeLabel => '59 Power';
  @override
  int get maxExchange => 1500;
  @override
  String get scoringNotice =>
      'Training profile; validate station category before official scoring.';
  @override
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station) => 3;
}

class IaruHfDefinition extends _NumericContestDefinition {
  const IaruHfDefinition();
  @override
  String get id => 'IARU-HF';
  @override
  String get name => 'IARU HF SSB';
  @override
  String get exchangeLabel => '59 ITU Zone';
  @override
  int get maxExchange => 90;
  @override
  String get scoringNotice =>
      'Single-band training score; country and zone multipliers.';
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
  String get name => 'JIDX SSB';
  @override
  String get exchangeLabel => '59 Prefecture';
  @override
  int get maxExchange => 47;
  @override
  String get scoringNotice =>
      'Training profile; Japanese-prefecture exchange practice.';
  @override
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station) => 1;
}

abstract class _NumericContestDefinition extends ContestDefinition {
  const _NumericContestDefinition();
  int get maxExchange;
  int pointsFor(QsoTableData qso, DxccManager dxcc, String station);

  @override
  ContestType create({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) => _NumericContestType(
    maxExchange: maxExchange,
    stationCallsign: stationCallsign,
    dxccManager: dxccManager,
    pointsFor: pointsFor,
  );
}

class _NumericContestType implements ContestType {
  _NumericContestType({
    required int maxExchange,
    required String stationCallsign,
    required DxccManager dxccManager,
    required _PointsFor pointsFor,
  }) : _exchangeManager = _NumericExchangeManager(maxExchange),
       _scoreCalculator = _NumericScoreCalculator(
         stationCallsign,
         dxccManager,
         pointsFor,
       );

  final _NumericExchangeManager _exchangeManager;
  final _NumericScoreCalculator _scoreCalculator;
  @override
  RegExp get allowExchangeRegex => RegExp('[0-9]');
  @override
  _NumericExchangeManager get exchangeManager => _exchangeManager;
  @override
  _NumericScoreCalculator get scoreCalculator => _scoreCalculator;
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
