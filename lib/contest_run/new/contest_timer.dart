import 'dart:async';

class ContestTimer {
  final void Function() onContestEnd;

  ContestTimer({required this.onContestEnd});

  Timer? _timer;

  Duration _elapseTime = Duration.zero;

  Duration get elapseTime => _elapseTime;

  /// The duration frozen when the run started. Settings may change mid-run; the
  /// remaining time and progress must not follow the live setting.
  Duration _totalDuration = Duration.zero;

  Duration get totalDuration => _totalDuration;

  bool _isPaused = false;

  bool get isPaused => _isPaused;

  DateTime? _pauseStartedAt;

  Duration _pausedDuration = Duration.zero;

  Duration get pausedDuration => _pausedDuration;

  /// Pause time including the pause currently in progress, used by the chip
  /// tooltip so the operator can see how long the run has been frozen.
  Duration get pausedDurationIncludingCurrent {
    final startedAt = _pauseStartedAt;
    return startedAt == null
        ? _pausedDuration
        : _pausedDuration + DateTime.now().difference(startedAt);
  }

  int _pauseCount = 0;

  int get pauseCount => _pauseCount;

  final _elapseTimeStreamController = StreamController<Duration>.broadcast();

  Stream<Duration> get elapseTimeStream => _elapseTimeStreamController.stream;

  void start(int durationInMinutes) {
    _totalDuration = Duration(minutes: durationInMinutes);
    _elapseTime = Duration.zero;
    _isPaused = false;
    _pauseStartedAt = null;
    _pausedDuration = Duration.zero;
    _pauseCount = 0;
    _startTicker();
  }

  /// Freezes the clock. The elapsed time is kept, and the ticker is cancelled
  /// so paused wall-clock time never counts as practice time.
  void pause() {
    if (_isPaused || _timer == null) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _isPaused = true;
    _pauseStartedAt = DateTime.now();
    _pauseCount++;
    _elapseTimeStreamController.sink.add(_elapseTime);
  }

  /// Continues from the frozen elapsed time. The ticker restarts on top of the
  /// accumulated seconds, so the pause span is excluded.
  void resume() {
    if (!_isPaused) {
      return;
    }
    final pausedAt = _pauseStartedAt;
    if (pausedAt != null) {
      _pausedDuration += DateTime.now().difference(pausedAt);
    }
    _pauseStartedAt = null;
    _isPaused = false;
    _startTicker();
  }

  void stop() {
    if (_isPaused) {
      final pausedAt = _pauseStartedAt;
      if (pausedAt != null) {
        _pausedDuration += DateTime.now().difference(pausedAt);
      }
      _pauseStartedAt = null;
      _isPaused = false;
    }
    _timer?.cancel();
    _timer = null;
  }

  void _startTicker() {
    _timer?.cancel();
    final baseSeconds = _elapseTime.inSeconds;
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      final elapseTime = Duration(seconds: baseSeconds + timer.tick);
      _elapseTime = elapseTime;
      _elapseTimeStreamController.sink.add(elapseTime);

      if (elapseTime >= _totalDuration) {
        onContestEnd();
      }
    });
  }
}
