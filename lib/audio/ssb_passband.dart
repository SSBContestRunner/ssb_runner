import 'dart:math';

/// Direct-form-I RBJ biquad.
///
/// Shared by the receiver noise bed and the in-signal SNR noise so both are
/// shaped by exactly the same SSB passband.
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  factory Biquad.lowPass(int sampleRate, double frequency, double q) {
    final omega = 2 * pi * frequency / sampleRate;
    final cosOmega = cos(omega);
    final alpha = sin(omega) / (2 * q);
    final a0 = 1 + alpha;
    return Biquad._(
      (1 - cosOmega) / 2 / a0,
      (1 - cosOmega) / a0,
      (1 - cosOmega) / 2 / a0,
      -2 * cosOmega / a0,
      (1 - alpha) / a0,
    );
  }

  factory Biquad.highPass(int sampleRate, double frequency, double q) {
    final omega = 2 * pi * frequency / sampleRate;
    final cosOmega = cos(omega);
    final alpha = sin(omega) / (2 * q);
    final a0 = 1 + alpha;
    return Biquad._(
      (1 + cosOmega) / 2 / a0,
      -(1 + cosOmega) / a0,
      (1 + cosOmega) / 2 / a0,
      -2 * cosOmega / a0,
      (1 - alpha) / a0,
    );
  }

  final double _b0;
  final double _b1;
  final double _b2;
  final double _a1;
  final double _a2;

  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;

  double process(double input) {
    final output =
        _b0 * input + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = input;
    _y2 = _y1;
    _y1 = output;
    return output;
  }

  void reset() {
    _x1 = 0;
    _x2 = 0;
    _y1 = 0;
    _y2 = 0;
  }
}

/// Shapes uniform white noise into the audio passband of an SSB receiver.
///
/// The cascade is a 2nd-order high-pass at 300 Hz plus a 4th-order Butterworth
/// low-pass at 2700 Hz — the same passband as the receiver noise bed, so the
/// in-signal SNR noise has exactly the colour of the floor instead of being
/// full-band white.
///
/// The output is normalised so that its RMS equals the RMS that the in-band
/// part of the same full-band white noise had (flat spectrum, uniform on
/// [-1, 1]). A given `snrNoise` therefore keeps the same effective SNR in the
/// passband even though the out-of-band hiss is gone.
class SsbNoiseShaper {
  SsbNoiseShaper({this.sampleRate = 24000})
      : _highPass = Biquad.highPass(sampleRate, lowHz, 0.70710678),
        _lowPassA = Biquad.lowPass(sampleRate, highHz, 0.54119610),
        _lowPassB = Biquad.lowPass(sampleRate, highHz, 1.30656296) {
    _gain = _calibrate();
  }

  /// Flat part of the emulated SSB audio passband.
  static const double lowHz = 300;
  static const double highHz = 2700;

  final int sampleRate;
  final Biquad _highPass;
  final Biquad _lowPassA;
  final Biquad _lowPassB;
  late final double _gain;

  /// Feeds one white sample (typically in [-1, 1]) through the passband.
  double process(double white) => _filter(white) * _gain;

  /// Clears the filter state; the caller normally keeps the state running so
  /// the shaped noise is continuous across clips.
  void reset() {
    _highPass.reset();
    _lowPassA.reset();
    _lowPassB.reset();
  }

  double _filter(double white) =>
      _lowPassB.process(_lowPassA.process(_highPass.process(white)));

  /// Measures the cascade's noise gain and returns the scale that restores the
  /// in-band RMS of full-band white noise. Uses its own fixed-seed generator so
  /// it never disturbs the session's audio sequence.
  double _calibrate() {
    const warmup = 2048;
    const samples = 24000;
    final random = Random(_calibrationSeed);
    for (var index = 0; index < warmup; index++) {
      _filter(random.nextDouble() * 2 - 1);
    }
    var sumSquares = 0.0;
    for (var index = 0; index < samples; index++) {
      final value = _filter(random.nextDouble() * 2 - 1);
      sumSquares += value * value;
    }
    final rms = sqrt(sumSquares / samples);
    if (rms == 0) {
      return 1;
    }
    // RMS of uniform white on [-1, 1], reduced by the fraction of its power
    // that lies inside the passband.
    const whiteRms = 0.5773502691896258;
    final inBand = sqrt((highHz - lowHz) / (sampleRate / 2));
    return whiteRms * inBand / rms;
  }

  static const int _calibrationSeed = 0x5D5B;
}
