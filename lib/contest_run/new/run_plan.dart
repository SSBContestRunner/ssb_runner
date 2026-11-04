import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/training/pending_replay.dart';

/// Which source the starting run took its plan from.
enum RunPlanSource { pending, settings }

/// Why an armed replay was abandoned. A replay is never merged with the
/// settings; the run either replays exactly what was recorded or starts a
/// fresh session from the ordinary settings.
enum ReplayAbortReason { eventsMissing, headerMismatch, contestUnknown }

/// The resolved parameters for one `startContest` call (design §7.5).
class RunPlan {
  const RunPlan({
    required this.definition,
    required this.modeId,
    required this.difficultyId,
    required this.questionSeed,
    required this.audioSeed,
    this.replayRunId,
    this.source = RunPlanSource.settings,
    this.abortedReason,
    this.abortedContestName,
    this.warnings = const [],
  });

  final ContestDefinition definition;
  final String modeId;
  final String difficultyId;
  final int questionSeed;
  final int audioSeed;

  /// Non-null means this run replays the recorded answers of that run id.
  final String? replayRunId;
  final RunPlanSource source;
  final ReplayAbortReason? abortedReason;

  /// The recording's display name, kept even when the replay is abandoned so
  /// the toast can say which session could not be replayed.
  final String? abortedContestName;
  final List<String> warnings;

  String get contestId => definition.id;
  String get contestName => definition.name;
  bool get isReplay => replayRunId != null;
}

/// The self-describing header written as the first event of every new run.
/// It only proves ownership of the recording; it never overrides a pending
/// replay (design §7.7).
class RecordedRunHeader {
  const RecordedRunHeader({
    required this.contestId,
    required this.contestName,
    required this.modeId,
    required this.difficultyId,
    required this.questionSeed,
    required this.audioSeed,
    this.accentId = 'auto',
    this.appVersion = '',
    this.replayOfRunId,
  });

  final String contestId;
  final String contestName;
  final String modeId;
  final String difficultyId;
  final int questionSeed;
  final int audioSeed;
  final String accentId;
  final String appVersion;
  final String? replayOfRunId;

  Map<String, Object?> toJson() => {
    'contestId': contestId,
    'contestName': contestName,
    'modeId': modeId,
    'difficultyId': difficultyId,
    'questionSeed': questionSeed,
    'audioSeed': audioSeed,
    'accentId': accentId,
    'appVersion': appVersion,
    'replayOfRunId': replayOfRunId,
  };

  factory RecordedRunHeader.fromJson(Map<String, dynamic> json) =>
      RecordedRunHeader(
        contestId: _stringOrUnknown(json['contestId']),
        contestName: _stringOrUnknown(json['contestName']),
        modeId: _stringOrUnknown(json['modeId']),
        difficultyId: _stringOrUnknown(json['difficultyId']),
        questionSeed: json['questionSeed'] as int? ?? 0,
        audioSeed: json['audioSeed'] as int? ?? 0,
        accentId: json['accentId'] as String? ?? 'auto',
        appVersion: json['appVersion'] as String? ?? '',
        replayOfRunId: json['replayOfRunId'] as String?,
      );

  static String _stringOrUnknown(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return unknownReplayField;
  }
}
