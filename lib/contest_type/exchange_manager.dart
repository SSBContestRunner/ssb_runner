import 'package:ssb_runner/training/session_random.dart';

abstract interface class ExchangeManager {
  /// The exchange the incoming [callerCallsign] transmits, derived from the
  /// caller's identity (CQ/ITU zone, prefecture, state/province or power).
  String generateExchange(
    SessionRandom random, {
    required String callerCallsign,
  });
  String processExchange(String exchange);
}