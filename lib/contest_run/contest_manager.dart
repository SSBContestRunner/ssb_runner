import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ssb_contest_runner/audio/audio_player.dart';
import 'package:ssb_contest_runner/audio/payload_to_audio.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_contest_runner/state_machine/state_machine.dart';
import 'package:uuid/uuid.dart';

class ContestManager {
  bool _isContestRunning = false;
  Timer? _timer;

  final _contestRunIdStreamController = StreamController<String>();
  Stream<String> get contestRunIdStream => _contestRunIdStreamController.stream;

  final _elapseTimeStreamController = StreamController<Duration>();
  Stream<Duration> get elapseTimeStream => _elapseTimeStreamController.stream;

  final _isContestRunningStreamController = StreamController<bool>();
  Stream<bool> get isContestRunningStream => _isContestRunningStreamController.stream;

  final _audioPlayer = AudioPlayer();

  late final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;

  ContestManager() {
    _stateMachine = initSingleCallRunStateMachine(
      initialState: WaitingSubmitCall(
        currentCallAnswer: 'BI1QJQ',
        currentExchangeAnswer: '230',
      ),
      transitionListener: (transition) {
        if (transition
            is! TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) {
          return;
        }

        final toState = transition.to;
        _playAudio(toState);
      },
    );
  }

  Future<void> _playAudio(SingleCallRunState toState) async {
    switch (toState) {
      case WaitingSubmitCall():
        final pcmData = await payloadToAudioData(toState.currentCallAnswer);
        await _playAudioInternal(pcmData);
        break;
      case WaitingSubmitExchange():
        _playAudioByPlayType(toState.audioPlayType);
        break;
      case QsoEnd():
        // TODO: Play TU QRZ
        break;
    }
  }

  Future<void> _playAudioByPlayType(AudioPlayType playType) async {
    switch (playType) {
      case NoPlay():
        _audioPlayer.stopPlay();
      case PlayExchange():
        final pcmData = await payloadToAudioData(playType.exchange);
        await _playAudioInternal(pcmData);
      case PlayCallExchange():
        final payload = playType.call + playType.exchange;
        final pcmData = await payloadToAudioData(payload);
        await _playAudioInternal(pcmData);
    }
  }

  Future<void> _playAudioInternal(Uint8List pcmData) async {
    if (!_audioPlayer.isStarted) {
      await _audioPlayer.startPlay();
    }

    _audioPlayer.addPcmData(pcmData);
  }

  void startContest(Duration duration) {
    final contestRunId = Uuid().v4();
    _contestRunIdStreamController.sink.add(contestRunId);

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      final elapseTime = Duration(seconds: timer.tick);
      _elapseTimeStreamController.sink.add(elapseTime);

      if (elapseTime >= duration) {
        _isContestRunning = false;
        _isContestRunningStreamController.sink.add(false);
        timer.cancel();
      }
    });

    final elapseTime = Duration.zero;
    _elapseTimeStreamController.sink.add(elapseTime);

    _isContestRunning = true;
    _isContestRunningStreamController.sink.add(true);
    _audioPlayer.startPlay();
  }

  void stopContest() {
    _timer?.cancel();
    _isContestRunning = false;
    _isContestRunningStreamController.sink.add(false);
  }

  void transition(SingleCallRunEvent event) {
    _stateMachine.transition(event);
  }
}
