import 'dart:async';

class ContestManager {
  bool isContestRunning = false;
  Timer? _timer;
  Duration leftTime = Duration.zero;

  void startContest(Duration duration) {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      leftTime = duration - Duration(seconds: timer.tick);

      if (leftTime.inSeconds <= 0) {
        isContestRunning = false;
        timer.cancel();
      }
    });

    isContestRunning = true;
  }

  void stopContest() {
    _timer?.cancel();
    isContestRunning = false;
  }
}
