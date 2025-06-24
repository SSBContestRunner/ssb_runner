sealed class AudioPlayType {}

class NoPlay extends AudioPlayType {}

class PlayExchange extends AudioPlayType {
  final String exchange;

  PlayExchange({required this.exchange});
}

class PlayCallExchange extends AudioPlayType {
  final String call;
  final String exchange;

  PlayCallExchange({required this.call, required this.exchange});
}
