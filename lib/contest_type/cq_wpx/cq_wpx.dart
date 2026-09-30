import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx_score_calculator.dart';
import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/training/session_random.dart';

class CqWpxContestType implements ContestType {
  late final WpxScoreCalculator _scoreCalculator;
  late final StationExchangeBuilder _builder;

  final _exchangeManager = _CqWpxExchangeManager();

  CqWpxContestType({
    required String stationCallsign,
    required DxccManager dxccManager,
    required StationExchangeConfig stationExchange,
  }) {
    _scoreCalculator = WpxScoreCalculator(
      stationCallsign: stationCallsign,
      dxccManager: dxccManager,
    );
    _builder = StationExchangeBuilder(
      plan: const MyExchangePlan(
        fields: [],
        sendsSerial: true,
        serialDigits: 3,
      ),
      config: stationExchange,
      stationCallsign: stationCallsign,
      dxccManager: dxccManager,
      exchangeAudioDigits: 3,
    );
  }

  @override
  ExchangeManager get exchangeManager => _exchangeManager;

  @override
  ScoreCalculator get scoreCalculator => _scoreCalculator;

  @override
  RegExp get allowExchangeRegex => RegExp('[0-9]');

  @override
  String buildMyExchange(int qsoNumber) => _builder.buildMyExchange(qsoNumber);

  @override
  String formatExchangeForAudio(String exchange) =>
      _builder.formatExchangeForAudio(exchange);
}

class _CqWpxExchangeManager implements ExchangeManager {
  @override
  String generateExchange(SessionRandom random) {
    final exchange = random.nextExchange(3000);
    return exchange.toString();
  }

  @override
  String processExchange(String exchange) {
    return exchange.replaceAll(RegExp(r'^0+(?=.)'), '');
  }
}
