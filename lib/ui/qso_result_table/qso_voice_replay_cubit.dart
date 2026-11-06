import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/qso_voice_replay_service.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';

enum QsoVoiceReplayNoticeKind { interrupted, stopped }

class QsoVoiceReplayNotice {
  const QsoVoiceReplayNotice({
    required this.seq,
    required this.kind,
    required this.fromCall,
    required this.toCall,
  });

  final int seq;
  final QsoVoiceReplayNoticeKind kind;
  final String fromCall;
  final String toCall;
}

class QsoVoiceReplayState {
  const QsoVoiceReplayState({
    this.playingId,
    this.doneId,
    this.interruptedId,
    this.notice,
  });

  /// Id of the row currently playing. Only one row can hold it (last wins).
  final int? playingId;

  /// Id of the row whose replay just finished.
  final int? doneId;

  /// Id of the row that was interrupted by a newer replay.
  final int? interruptedId;

  final QsoVoiceReplayNotice? notice;
}

class QsoVoiceReplayCubit extends Cubit<QsoVoiceReplayState> {
  QsoVoiceReplayCubit({
    required ContestManager contestManager,
    required AudioLoader audioLoader,
    required AudioPlayer audioPlayer,
  }) : _contestManager = contestManager,
       _service = QsoVoiceReplayService(
         audioLoader: audioLoader,
         audioPlayer: audioPlayer,
         appSettings: contestManager.appSettings,
       ),
       super(const QsoVoiceReplayState()) {
    _phaseSubscription = contestManager.sessionPhaseStream.listen(_onPhase);
    _sessionIdle = !contestManager.isContestRunning;
  }

  final ContestManager _contestManager;
  final QsoVoiceReplayService _service;

  StreamSubscription<ContestSessionPhase>? _phaseSubscription;
  bool _sessionIdle = true;
  int _token = 0;
  int _noticeSeq = 0;
  QsoResult? _current;

  @override
  Future<void> close() async {
    await _phaseSubscription?.cancel();
    _token++;
    if (identical(_contestManager.sessionPhase, ContestSessionPhase.idle)) {
      _service.finish();
    }
    return super.close();
  }

  void _onPhase(ContestSessionPhase phase) {
    final idle = phase == ContestSessionPhase.idle;
    if (_sessionIdle && idle) {
      return;
    }
    _sessionIdle = idle;
    if (idle || _current == null) {
      return;
    }

    // A training run took the player over: drop the replay UI state without
    // touching the contest audio.
    _token++;
    _current = null;
    _service.abandon();
    emit(const QsoVoiceReplayState());
  }

  void play(QsoResult row) {
    if (!row.canReplay || !_sessionIdle) {
      return;
    }

    if (state.playingId == row.id) {
      stop();
      return;
    }

    final previous = _current;
    final token = ++_token;
    _current = row;

    if (previous != null) {
      log.info(
        '✕ 打断 ${previous.correctCall}',
        tag: 'qso.replay',
        fields: <String, Object?>{
          'interrupted': previous.correctCall,
          'next': row.correctCall,
        },
      );
      _service.interrupt();
      _noticeSeq++;
      emit(
        QsoVoiceReplayState(
          playingId: row.id,
          interruptedId: previous.id,
          notice: QsoVoiceReplayNotice(
            seq: _noticeSeq,
            kind: QsoVoiceReplayNoticeKind.interrupted,
            fromCall: previous.correctCall,
            toCall: row.correctCall,
          ),
        ),
      );
    } else {
      emit(QsoVoiceReplayState(playingId: row.id));
    }

    unawaited(_run(row, token));
  }

  Future<void> _run(QsoResult row, int token) async {
    final request = _requestFor(row);
    if (request == null) {
      log.warn(
        'replay skipped: missing replay metadata',
        tag: 'qso.replay',
        fields: <String, Object?>{'call': row.correctCall},
      );
      _finishState(token);
      return;
    }

    _service.prepare();
    final pcm = await _service.compose(request);
    if (token != _token) {
      return;
    }
    if (pcm.isEmpty) {
      log.warn(
        'replay produced no audio',
        tag: 'qso.replay',
        fields: <String, Object?>{'call': request.callsign},
      );
      _finishState(token);
      return;
    }
    if (!_sessionIdle) {
      _service.abandon();
      return;
    }

    log.info(
      '▶ ${row.correctCall} ${row.serial}',
      tag: 'qso.replay',
      fields: <String, Object?>{
        'call': row.correctCall,
        'serial': row.serial,
        'accent': request.accentDir,
      },
    );
    _service.play(pcm);

    while (token == _token && _service.isPlaying) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (token != _token) {
      return;
    }

    emit(QsoVoiceReplayState(doneId: row.id));
    // The audio already ended; a following click must not report an
    // interruption of the finished row.
    _current = null;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (token != _token) {
      return;
    }
    emit(const QsoVoiceReplayState());
    if (_sessionIdle) {
      _service.finish();
    } else {
      _service.abandon();
    }
  }

  void stop() {
    final current = _current;
    if (current == null) {
      return;
    }

    _token++;
    _current = null;
    log.info(
      '✕ 打断 ${current.correctCall}',
      tag: 'qso.replay',
      fields: <String, Object?>{'call': current.correctCall},
    );
    _service.interrupt();
    _service.finish();
    _noticeSeq++;
    emit(
      QsoVoiceReplayState(
        interruptedId: current.id,
        notice: QsoVoiceReplayNotice(
          seq: _noticeSeq,
          kind: QsoVoiceReplayNoticeKind.stopped,
          fromCall: current.correctCall,
          toCall: '',
        ),
      ),
    );
  }

  void _finishState(int token) {
    if (token != _token) {
      return;
    }
    emit(const QsoVoiceReplayState());
    _current = null;
    if (_sessionIdle) {
      _service.finish();
    } else {
      _service.abandon();
    }
  }

  QsoVoiceReplayRequest? _requestFor(QsoResult row) {
    final accentDir = row.accentDir;
    final phonicTypeId = row.phonicTypeId;
    final callDirs = row.callPhonicDirs;
    final exchangeDirs = row.exchangePhonicDirs;
    final contestType = _contestManager.contestType;
    if (accentDir == null ||
        phonicTypeId == null ||
        callDirs == null ||
        exchangeDirs == null ||
        contestType == null) {
      return null;
    }

    final phonicType = PhonicType.values.firstWhere(
      (type) => type.name == phonicTypeId,
      orElse: () => PhonicType.standard,
    );

    return QsoVoiceReplayRequest(
      callsign: row.correctCall,
      exchangeAudioText: contestType.formatExchangeForAudio(
        row.correctExchange,
      ),
      accentDir: accentDir,
      phonicType: phonicType,
      callPhonicDirs: callDirs,
      exchangePhonicDirs: exchangeDirs,
    );
  }
}
