final supportedContests = [Contest(id: 'CQ-WPX', name: 'CQ WPX', exchange: '59 #')];
final supportedContestModes = [
  ContestMode(id: 'single-call', name: 'Single Call'),
];

class Contest {
  final String id;
  final String name;
  final String exchange;

  Contest({required this.id, required this.name, required this.exchange});
}

class ContestMode {
  final String id;
  final String name;

  ContestMode({required this.id, required this.name});
}
