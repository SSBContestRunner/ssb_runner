import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// Serves the exact answers recorded in a run's event log (record first,
/// recompute as a fallback), so a historical session replays even after the
/// generation algorithm changes (design §5.5).
class ReplayAnswerSource implements AnswerSource {
  ReplayAnswerSource(this._answers, {AnswerSource? fallback})
    : _fallback = fallback;

  final List<ContestAnswer> _answers;
  final AnswerSource? _fallback;
  int _index = 0;

  int get length => _answers.length;
  bool get isExhausted => _index >= _answers.length;

  factory ReplayAnswerSource.fromEvents(
    List<TrainingRunEvent> events, {
    AnswerSource? fallback,
  }) {
    final answers = events
        .where((event) => event.type == 'answer')
        .map(
          (event) => ContestAnswer(
            callSign: event.callsign,
            exchange: event.exchange,
            pileupCallsigns: event.pileupCallsigns,
            mode: TrainingMode.fromId(event.modeId),
          ),
        )
        .toList();
    return ReplayAnswerSource(answers, fallback: fallback);
  }

  @override
  ContestAnswer generateAnswer() {
    if (_index < _answers.length) {
      return _answers[_index++];
    }
    final fallback = _fallback;
    if (fallback != null) {
      return fallback.generateAnswer();
    }
    throw StateError('Replay log is exhausted and no fallback is available');
  }
}

/// Records every served answer through [onAnswer] before returning it, for
/// both live generation and replay.
class RecordingAnswerSource implements AnswerSource {
  RecordingAnswerSource(this._inner, this._onAnswer);

  final AnswerSource _inner;
  final void Function(ContestAnswer answer)? _onAnswer;

  @override
  ContestAnswer generateAnswer() {
    final answer = _inner.generateAnswer();
    _onAnswer?.call(answer);
    return answer;
  }
}
