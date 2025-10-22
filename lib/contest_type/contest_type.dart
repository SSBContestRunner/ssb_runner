import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';

abstract interface class ContestType {
  abstract final RegExp allowExchangeRegex;
  abstract final ScoreCalculator scoreCalculator;
  abstract final ExchangeManager exchangeManager;
}
