import 'package:ssb_runner/contest_run/data/score_data.dart';

class ScoreAreaData {
  final ScoreData rawScore;
  final ScoreData verifiedScore;

  ScoreAreaData({required this.rawScore, required this.verifiedScore});

  ScoreAreaData copyWith({ScoreData? rawScore, ScoreData? verifiedScore}) {
    return ScoreAreaData(
      rawScore: rawScore ?? this.rawScore,
      verifiedScore: verifiedScore ?? this.verifiedScore,
    );
  }
}
