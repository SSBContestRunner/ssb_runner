sealed class AudioPlayType {}

class NoPlay extends AudioPlayType {}

class PlayCall extends AudioPlayType {
  final String callToPlay;
  final bool isMe;

  PlayCall({required this.callToPlay, this.isMe = false});
}

class PlayPileup extends AudioPlayType {
  PlayPileup({required this.calls});
  final List<String> calls;
}

class PlaySearchAndPounce extends AudioPlayType {
  PlaySearchAndPounce({required this.call});
  final String call;
}

/// Keeps the raw exchange; the contest formats it for playback
/// (leading-zero width is contest specific, see StationExchangeBuilder).
class PlayExchange extends AudioPlayType {
  final String exchangeToPlay;
  final bool isMe;

  PlayExchange({required String exchange, required this.isMe})
    : exchangeToPlay = exchange;
}

class PlayCallExchange extends AudioPlayType {
  final String call;
  final String exchangeToPlay;
  final bool isMe;

  PlayCallExchange({
    required this.call,
    required String exchange,
    required this.isMe,
  }) : exchangeToPlay = exchange;
}
