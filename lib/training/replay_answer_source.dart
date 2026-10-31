import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// Serves recorded answers exactly, including historical duplicates. The end
/// of the recording ends replay; reseeding here would restart at question one.
class ReplayAnswerSource implements AnswerSource {
  ReplayAnswerSource(List<ContestAnswer> answers)
    : _answers = List.unmodifiable(answers);

  final List<ContestAnswer> _answers;
  int _index = 0;

  int get length => _answers.length;
  bool get isExhausted => _index >= _answers.length;

  factory ReplayAnswerSource.fromEvents(List<TrainingRunEvent> events) {
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
    return ReplayAnswerSource(answers);
  }

  @override
  ContestAnswer generateAnswer({String? requeueCallsign}) {
    // The recording already reflects the requeue: the abandoned station was
    // part of the pileup list when the answer was served live.
    if (_index < _answers.length) {
      return _answers[_index++];
    }
    throw const AnswerSourceExhausted('replay_completed');
  }
}

/// Records every served answer through [onAnswer] before returning it, for
/// both live generation and replay.
class RecordingAnswerSource implements AnswerSource {
  RecordingAnswerSource(this._inner, this._onAnswer);

  final AnswerSource _inner;
  final void Function(ContestAnswer answer)? _onAnswer;

  @override
  ContestAnswer generateAnswer({String? requeueCallsign}) {
    final answer = _inner.generateAnswer(requeueCallsign: requeueCallsign);
    _onAnswer?.call(answer);
    return answer;
  }
}
