import 'dart:convert';

import 'package:ssb_runner/training/session_review.dart';

/// Marker stored when a persisted replay field is missing or unreadable. The
/// value is never guessed: a replay armed with unknown fields is aborted at
/// run start instead of silently falling back to another contest.
const String unknownReplayField = 'unknown';

/// The next session's replay intent (design §7.1).
///
/// It describes what to replay, not what the operator currently configured,
/// so arming it never changes the ordinary contest/mode/difficulty settings.
class PendingReplay {
  const PendingReplay({
    required this.runId,
    required this.contestId,
    required this.contestName,
    required this.modeId,
    required this.difficultyId,
    required this.questionSeed,
    required this.audioSeed,
    required this.armedAtUtc,
  });

  final String runId;
  final String contestId;
  final String contestName;
  final String modeId;
  final String difficultyId;
  final int questionSeed;
  final int audioSeed;
  final DateTime armedAtUtc;

  bool get hasKnownContest => contestId != unknownReplayField;
  bool get hasKnownMode => modeId != unknownReplayField;
  bool get hasKnownDifficulty => difficultyId != unknownReplayField;

  factory PendingReplay.fromReview(
    TrainingRunReview review, {
    DateTime? armedAtUtc,
  }) => PendingReplay(
    runId: review.metadata.runId,
    contestId: review.metadata.contestId,
    contestName: review.metadata.contestName,
    modeId: review.metadata.modeId,
    difficultyId: review.metadata.difficultyId,
    questionSeed: review.metadata.questionSeed,
    audioSeed: review.metadata.audioSeed,
    armedAtUtc: armedAtUtc ?? DateTime.now().toUtc(),
  );

  Map<String, Object> toJson() => {
    'runId': runId,
    'contestId': contestId,
    'contestName': contestName,
    'modeId': modeId,
    'difficultyId': difficultyId,
    'questionSeed': questionSeed,
    'audioSeed': audioSeed,
    'armedAtUtc': armedAtUtc.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  factory PendingReplay.fromJson(Map<String, dynamic> json) => PendingReplay(
    runId: _stringOrUnknown(json['runId']),
    contestId: _stringOrUnknown(json['contestId']),
    contestName: _stringOrUnknown(json['contestName']),
    modeId: _stringOrUnknown(json['modeId']),
    difficultyId: _stringOrUnknown(json['difficultyId']),
    questionSeed: json['questionSeed'] as int? ?? 0,
    audioSeed: json['audioSeed'] as int? ?? 0,
    armedAtUtc: _parseDate(json['armedAtUtc']),
  );

  static String _stringOrUnknown(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return unknownReplayField;
  }

  static DateTime _parseDate(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
