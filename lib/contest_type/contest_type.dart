import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';

abstract interface class ContestType {
  abstract final RegExp allowExchangeRegex;
  abstract final ScoreCalculator scoreCalculator;
  abstract final ExchangeManager exchangeManager;

  /// The operator's own exchange for the 1-based [qsoNumber], ready to speak.
  String buildMyExchange(int qsoNumber);

  /// Received exchange -> spoken form for the current contest.
  String formatExchangeForAudio(String exchange);
}
