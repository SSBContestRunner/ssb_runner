final supportedContest = [Contest(id: 'CQ-WPX', exchange: '59 #')];
final contestModes = [ContestMode(id: 'single-call', name: 'Single Call')];

class Contest {
  final String id;
  final String exchange;

  Contest({required this.id, required this.exchange});
}

class ContestMode {
  final String id;
  final String name;

  ContestMode({required this.id, required this.name});
}
