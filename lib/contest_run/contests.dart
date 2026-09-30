import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// Compatibility views derived from the single source of truth
/// ([ContestRegistry]). New code should use [ContestRegistry] /
/// [ContestDefinition] directly; these legacy types exist so older callers such
/// as [AppSettings] keep compiling without a breaking rename.
final supportedContests = ContestRegistry.all
    .map(
      (definition) => Contest(
        id: definition.id,
        name: definition.name,
        exchange: definition.exchangeLabel,
      ),
    )
    .toList(growable: false);

/// Derived from [TrainingMode]; kept as a compatibility view for callers that
/// still consume the legacy [ContestMode] type.
final supportedContestModes = TrainingMode.values
    .map((mode) => ContestMode(id: mode.id, name: mode.label))
    .toList(growable: false);

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
