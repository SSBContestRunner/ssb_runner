import 'dart:math';

import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx_score_calculator.dart';
import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';

class CqWpxContestType implements ContestType {
  late final WpxScoreCalculator _scoreCalculator;

  final _exchangeManager = _CqWpxExchangeManager();

  CqWpxContestType({
    required String stationCallsign,
    required DxccManager dxccManager,
  }) {
    _scoreCalculator = WpxScoreCalculator(
      stationCallsign: stationCallsign,
      dxccManager: dxccManager,
    );
  }

  @override
  ExchangeManager get exchangeManager => _exchangeManager;

  @override
  ScoreCalculator get scoreCalculator => _scoreCalculator;

  @override
  RegExp get allowExchangeRegex => RegExp('[0-9]');
}

class _CqWpxExchangeManager implements ExchangeManager {
  final _random = Random();

  @override
  String generateExchange() {
    final exchange = _random.nextInt(3000) + 1;
    return exchange.toString();
  }

  @override
  String processExchange(String exchange) {
    return exchange.replaceAll(RegExp(r'^0+(?=.)'), '');
  }
}
