import 'dart:math';

/// The single random source for a training session.
///
/// The seed is split into independent sub-streams per domain, so drawing one
/// extra callsign cannot shift the exchange, phonic or audio sequences (Dart's
/// [Random] is sequence-coupled). This is what makes `questionSeed` and
/// `audioSeed` independently reproducible (design §5.2).
class SessionRandom {
  SessionRandom._(
    this._callsign,
    this._exchange,
    this._phonic,
    this._audio,
    this.seed,
  );

  factory SessionRandom(int seed) => SessionRandom._(
    Random(_derive(seed, 'callsign')),
    Random(_derive(seed, 'exchange')),
    Random(_derive(seed, 'phonic')),
    Random(_derive(seed, 'audio')),
    seed,
  );

  final Random _callsign;
  final Random _exchange;
  final Random _phonic;
  final Random _audio;

  /// The seed this instance was derived from.
  final int seed;

  int nextCallsignIndex(int length) => _callsign.nextInt(length);

  /// Draws an exchange in `1..max` inclusive.
  int nextExchange(int max) => _exchange.nextInt(max) + 1;

  int nextPhonicType(int max) => _phonic.nextInt(max);

  double nextAudioUnit() => _audio.nextDouble();

  /// Stable, allocation-free string mix so the derivation never depends on the
  /// runtime's hash seed.
  static int _derive(int seed, String tag) {
    var hash = seed & 0x7fffffff;
    for (final unit in tag.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
