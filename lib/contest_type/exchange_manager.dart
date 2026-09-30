import 'package:ssb_runner/training/session_random.dart';

abstract interface class ExchangeManager {
  String generateExchange(SessionRandom random);
  String processExchange(String exchange);
}