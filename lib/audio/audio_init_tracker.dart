import 'dart:async';

/// Lifecycle state of the audio engine initialisation.
enum AudioInitState {
  /// `start()` was never called (or audio was skipped before it).
  neverStarted,

  /// `start()` was called and the initialisation has not finished yet.
  running,

  /// The initialisation finished successfully.
  completed,

  /// The initialisation threw; the engine may still exist in native code.
  failed,
}

/// Tracks whether the audio initialisation has settled.
///
/// The exit path needs to know whether SoLoud is "never started", "done" or
/// "still initialising": answering the platform's exit request while the
/// engine is half initialised makes the plugin's DLL detach wait forever inside
/// `ExitProcess`, after the Dart VM is gone (see
/// `docs/design/desktop_exit_design.md` §2.3).
///
/// This class only records a state and one future. It does not poll, start
/// timers or change when the initialisation itself is started, so wrapping the
/// existing fire-and-forget call keeps the startup path unchanged.
class AudioInitTracker {
  AudioInitState _state = AudioInitState.neverStarted;
  Completer<void>? _settled;

  AudioInitState get state => _state;

  /// Completes once a running initialisation finished, successfully or not.
  ///
  /// Already complete when the initialisation never started, so callers do not
  /// have to branch on the state.
  Future<void> get settled => _settled?.future ?? Future<void>.value();

  /// Starts [initialise] and returns its future, recording the outcome.
  ///
  /// Must be called once, from the boot sequence, and must wrap the existing
  /// call in place: awaiting anything here would move the engine start onto the
  /// critical startup path.
  Future<void> start(Future<void> Function() initialise) {
    assert(
      _state == AudioInitState.neverStarted,
      'AudioInitTracker.start() may only be called once',
    );
    final settled = _settled = Completer<void>();
    _state = AudioInitState.running;
    return _run(initialise, settled);
  }

  /// Completes with `true` once the initialisation settled, or with `false`
  /// when it is still running after [timeout].
  ///
  /// Exit path only. A `false` answer means the engine may be half initialised,
  /// so the process must not answer the exit request and let `ExitProcess` run.
  Future<bool> settledWithin(Duration timeout) {
    if (_state != AudioInitState.running) {
      return Future<bool>.value(true);
    }
    return settled.then((_) => true).timeout(timeout, onTimeout: () => false);
  }

  Future<void> _run(
    Future<void> Function() initialise,
    Completer<void> settled,
  ) async {
    try {
      await initialise();
      _state = AudioInitState.completed;
    } catch (_) {
      // A failed init still created the native player, so it is not the same
      // as "never initialised"; it only counts as settled.
      _state = AudioInitState.failed;
      rethrow;
    } finally {
      settled.complete();
    }
  }
}
