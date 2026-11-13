import 'dart:async';
import 'dart:ffi';

/// Phase values understood by `ssb_boot_beat` in the Windows runner.
const int beatPhasePreFrame = 0;
const int beatPhaseBooting = 1;
const int beatPhaseFirstFrame = 2;
const int beatPhaseReady = 3;

/// Signature of the native heartbeat.
typedef BootBeatFn = void Function(int phase, int step);

typedef _NativeBootBeat = Void Function(Int32, Int32);

/// Resolves `ssb_boot_beat` from the current process, or null when the symbol
/// is unavailable (non-Windows builds).
BootBeatFn? loadBootBeat(DynamicLibrary library) {
  try {
    return library.lookupFunction<_NativeBootBeat, BootBeatFn>('ssb_boot_beat');
  } on ArgumentError {
    return null;
  }
}

/// Maps a [BootTrace.phase] value to the native enum.
int bootPhaseValue(String phase) {
  switch (phase) {
    case 'booting':
      return beatPhaseBooting;
    case 'firstFrame':
      return beatPhaseFirstFrame;
    case 'ready':
      return beatPhaseReady;
    default:
      return beatPhasePreFrame;
  }
}

/// Periodic UI-isolate heartbeat for the native startup watchdog.
///
/// The heartbeat only writes atomics on the native side: no file, no log and no
/// extra isolate. It sends once immediately (proving that `main()` executed)
/// and then every [interval] until the boot trace reports `ready`.
class BootBeat {
  BootBeat({
    required this._beat,
    required this._phase,
    required this._step,
    this._interval = const Duration(seconds: 2),
  });

  final BootBeatFn _beat;
  final String Function() _phase;
  final int Function() _step;
  final Duration _interval;

  Timer? _timer;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) {
      return;
    }
    if (_send()) {
      return;
    }
    _timer = Timer.periodic(_interval, (_) => _send());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Sends one heartbeat. Returns true when the app is ready and the timer was
  /// stopped, so [start] does not schedule it.
  bool _send() {
    final phase = bootPhaseValue(_phase());
    _beat(phase, _step());
    if (phase == beatPhaseReady) {
      stop();
      return true;
    }
    return false;
  }
}
