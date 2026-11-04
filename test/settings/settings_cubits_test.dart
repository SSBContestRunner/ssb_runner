import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'cubits follow direct settings writes and ignore unchanged values',
    () async {
      final settings = await _settings();
      final contestCubit = ContestSettingCubit(appSettings: settings);
      final optionsCubit = TrainingOptionsCubit(settings);
      final callsignCubit = StationCallsignCubit(appSettings: settings);
      addTearDown(() async {
        await contestCubit.close();
        await optionsCubit.close();
        await callsignCubit.close();
      });

      var contestEmits = 0;
      var optionEmits = 0;
      var callsignEmits = 0;
      contestCubit.stream.listen((_) => contestEmits++);
      optionsCubit.stream.listen((_) => optionEmits++);
      callsignCubit.stream.listen((_) => callsignEmits++);

      settings.contestId = 'CQ-WW-SSB';
      expect(contestCubit.state.id, 'CQ-WW-SSB');
      await pumpEventQueue();
      expect(contestEmits, 1);

      settings.difficulty = TrainingDifficulty.advanced;
      settings.contestDuration = 30;
      expect(optionsCubit.state.difficulty, TrainingDifficulty.advanced);
      expect(optionsCubit.state.duration, 30);
      expect(optionsCubit.durationController.text, '30');
      await pumpEventQueue();
      expect(optionEmits, 2);

      settings.stationCallsign = 'BI1QJQ';
      expect(callsignCubit.state, 'BI1QJQ');
      await pumpEventQueue();
      expect(callsignEmits, 1);

      // A revision bump with an identical value must not stream a duplicate.
      settings.contestId = 'CQ-WW-SSB';
      settings.difficulty = TrainingDifficulty.advanced;
      await pumpEventQueue();
      expect(contestEmits, 1);
      expect(optionEmits, 2);
    },
  );

  test(
    'armed replays project effective values and lock every write path',
    () async {
      final settings = await _settings();
      settings
        ..contestId = 'CQ-WW-SSB'
        ..contestModeId = TrainingMode.run.id
        ..difficulty = TrainingDifficulty.advanced;
      final contestCubit = ContestSettingCubit(appSettings: settings);
      final optionsCubit = TrainingOptionsCubit(settings);
      addTearDown(() async {
        await contestCubit.close();
        await optionsCubit.close();
      });

      settings.armReplay(
        PendingReplay(
          runId: 'wpx-run',
          contestId: 'CQ-WPX',
          contestName: 'CQ WPX',
          modeId: TrainingMode.pileup.id,
          difficultyId: TrainingDifficulty.beginner.id,
          questionSeed: 42,
          audioSeed: 43,
          armedAtUtc: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(contestCubit.state.id, 'CQ-WPX');
      expect(optionsCubit.state.mode, TrainingMode.pileup);
      expect(optionsCubit.state.difficulty, TrainingDifficulty.beginner);
      expect(settings.contestId, 'CQ-WW-SSB');
      expect(settings.contestModeId, TrainingMode.run.id);
      expect(settings.difficulty, TrainingDifficulty.advanced);

      // Cubit writers are the first defence layer.
      contestCubit.changeContest('ARRL-DX');
      optionsCubit.setMode(TrainingMode.run);
      optionsCubit.setDifficulty(TrainingDifficulty.standard);

      // Direct settings writes are the second layer; the snapshot stays the
      // single source of what the next run will use.
      settings.contestId = 'ARRL-DX';
      settings.contestModeId = TrainingMode.run.id;
      settings.difficulty = TrainingDifficulty.standard;

      expect(contestCubit.state.id, 'CQ-WPX');
      expect(optionsCubit.state.mode, TrainingMode.pileup);
      expect(optionsCubit.state.difficulty, TrainingDifficulty.beginner);
      expect(settings.contestId, 'CQ-WW-SSB');
      expect(settings.contestModeId, TrainingMode.run.id);
      expect(settings.difficulty, TrainingDifficulty.advanced);

      settings.clearPendingReplay();

      expect(contestCubit.state.id, 'CQ-WW-SSB');
      expect(optionsCubit.state.mode, TrainingMode.run);
      expect(optionsCubit.state.difficulty, TrainingDifficulty.advanced);
    },
  );
}

Future<AppSettings> _settings() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  return AppSettings(prefs: prefs);
}
