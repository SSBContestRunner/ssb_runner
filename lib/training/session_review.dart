import 'dart:convert';

import 'package:ssb_runner/db/app_database.dart';

class TrainingRunMetadata {
  const TrainingRunMetadata({
    required this.runId,
    required this.contestId,
    required this.contestName,
    required this.modeId,
    required this.difficultyId,
    required this.questionSeed,
    required this.audioSeed,
    required this.startedAt,
    this.appVersion = '',
  });

  final String runId;
  final String contestId;
  final String contestName;
  final String modeId;
  final String difficultyId;

  /// Determines the question sequence (callsign, exchange, pile-up, phonic).
  final int questionSeed;

  /// Determines the audio environment (noise bed, SNR noise, QSB phase).
  final int audioSeed;
  final String appVersion;
  final DateTime startedAt;
}

/// One recorded answer in a run. The replay engine replays these recorded
/// answers rather than recomputing them, so history stays replayable even if
/// the generation algorithm changes later (design §5.5).
class TrainingRunEvent {
  const TrainingRunEvent({
    required this.elapsedMs,
    required this.type,
    required this.callsign,
    required this.exchange,
    this.pileupCallsigns = const [],
    this.modeId = '',
  });

  final int elapsedMs;

  /// answer / submit / nocopy / worked-before
  final String type;
  final String callsign;
  final String exchange;
  final List<String> pileupCallsigns;
  final String modeId;

  Map<String, Object> toJson() => {
    'elapsedMs': elapsedMs,
    'type': type,
    'callsign': callsign,
    'exchange': exchange,
    'pileupCallsigns': pileupCallsigns,
    'modeId': modeId,
  };

  factory TrainingRunEvent.fromJson(Map<String, dynamic> json) =>
      TrainingRunEvent(
        elapsedMs: json['elapsedMs'] as int? ?? 0,
        type: json['type'] as String? ?? 'answer',
        callsign: json['callsign'] as String? ?? '',
        exchange: json['exchange'] as String? ?? '',
        pileupCallsigns:
            (json['pileupCallsigns'] as List<dynamic>?)
                ?.map((item) => item as String)
                .toList() ??
            const [],
        modeId: json['modeId'] as String? ?? '',
      );
}

class TrainingRunLog {
  const TrainingRunLog({
    required this.metadata,
    required this.events,
    required this.review,
  });

  final TrainingRunMetadata metadata;
  final List<TrainingRunEvent> events;
  final TrainingRunReview review;
}

class TrainingRunReview {
  const TrainingRunReview({
    required this.metadata,
    required this.endedAt,
    required this.qsoCount,
    required this.correctCount,
    required this.callsignErrors,
    required this.exchangeErrors,
    required this.score,
  });

  final TrainingRunMetadata metadata;
  final DateTime endedAt;
  final int qsoCount;
  final int correctCount;
  final int callsignErrors;
  final int exchangeErrors;
  final int score;

  double get accuracy => qsoCount == 0 ? 0 : correctCount / qsoCount;
  Duration get duration => endedAt.difference(metadata.startedAt);
  double get qsosPerHour =>
      duration.inSeconds == 0 ? 0 : qsoCount * 3600 / duration.inSeconds;

  factory TrainingRunReview.fromQsos({
    required TrainingRunMetadata metadata,
    required List<QsoTableData> qsos,
    required int score,
  }) {
    final correct = qsos
        .where(
          (qso) =>
              qso.callsign == qso.callsignCorrect &&
              qso.exchange == qso.exchangeCorrect,
        )
        .length;
    return TrainingRunReview(
      metadata: metadata,
      endedAt: DateTime.now().toUtc(),
      qsoCount: qsos.length,
      correctCount: correct,
      callsignErrors: qsos
          .where((qso) => qso.callsign != qso.callsignCorrect)
          .length,
      exchangeErrors: qsos
          .where((qso) => qso.exchange != qso.exchangeCorrect)
          .length,
      score: score,
    );
  }

  Map<String, Object> toJson() => {
    'runId': metadata.runId,
    'contestId': metadata.contestId,
    'contestName': metadata.contestName,
    'modeId': metadata.modeId,
    'difficultyId': metadata.difficultyId,
    'questionSeed': metadata.questionSeed,
    'audioSeed': metadata.audioSeed,
    'appVersion': metadata.appVersion,
    'startedAt': metadata.startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'qsoCount': qsoCount,
    'correctCount': correctCount,
    'callsignErrors': callsignErrors,
    'exchangeErrors': exchangeErrors,
    'score': score,
  };

  String encode() => jsonEncode(toJson());

  factory TrainingRunReview.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    // Backward compatibility: pre-seed versions stored a single `seed`.
    final legacySeed = json['seed'] as int? ?? 0;
    final questionSeed = json['questionSeed'] as int? ?? legacySeed;
    final audioSeed = json['audioSeed'] as int? ?? legacySeed;
    return TrainingRunReview(
      metadata: TrainingRunMetadata(
        runId: json['runId'] as String,
        contestId: json['contestId'] as String,
        contestName: json['contestName'] as String,
        modeId: json['modeId'] as String,
        difficultyId: json['difficultyId'] as String,
        questionSeed: questionSeed,
        audioSeed: audioSeed,
        appVersion: json['appVersion'] as String? ?? '',
        startedAt: DateTime.parse(json['startedAt'] as String),
      ),
      endedAt: DateTime.parse(json['endedAt'] as String),
      qsoCount: json['qsoCount'] as int,
      correctCount: json['correctCount'] as int,
      callsignErrors: json['callsignErrors'] as int,
      exchangeErrors: json['exchangeErrors'] as int,
      score: json['score'] as int,
    );
  }
}
