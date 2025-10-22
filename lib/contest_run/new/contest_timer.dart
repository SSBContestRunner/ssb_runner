import 'dart:async';

class ContestTimer {
  final void Function() onContestEnd;

  ContestTimer({required this.onContestEnd});

  Timer? _timer;

  Duration _elapseTime = Duration.zero;

  Duration get elapseTime => _elapseTime;

  final _elapseTimeStreamController = StreamController<Duration>.broadcast();

  Stream<Duration> get elapseTimeStream => _elapseTimeStreamController.stream;

  void start(int durationInMinutes) {
    final duration = Duration(minutes: durationInMinutes);

    _elapseTime = Duration.zero;

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      final elapseTime = Duration(seconds: timer.tick);
      _elapseTime = elapseTime;
      _elapseTimeStreamController.sink.add(elapseTime);

      if (elapseTime >= duration) {
        onContestEnd();
      }
    });
  }

  void stop() {
    _timer?.cancel();
  }
}
