class ScoreData {
  final int count;
  final int multiple;
  final int score;

  ScoreData({required this.count, required this.multiple, required this.score});

  ScoreData.initial(): this(count: 0, multiple: 0, score: 0);

  ScoreData copyWith({int? count, int? multiple, int? score}) {
    return ScoreData(
      count: count ?? this.count,
      multiple: multiple ?? this.multiple,
      score: score ?? this.score,
    );
  }
}
