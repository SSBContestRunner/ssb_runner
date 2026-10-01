import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_settings/main_settings.dart';
import 'package:ssb_runner/ui/main_settings/options_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Options dialogs can read AppSettings scoped below the Navigator', (
    tester,
  ) async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettings(prefs: prefs);

    // None of the dialogs may touch the database, so a lazy executor keeps the
    // test free of platform channels and the native sqlite library.
    final database = AppDatabase(
      LazyDatabase(
        () async => throw StateError(
          'The settings dialogs must not touch the database.',
        ),
      ),
    );

    final contestManager = ContestManager(
      contestDataManager: ContestDataManager(
        audioLoader: AudioLoader(),
        audioPlayer: AudioPlayer(),
        appSettings: settings,
        appDatabase: database,
        callsignLoader: CallsignLoader(),
        dxccManager: DxccManager(database: database),
        inputHandler: ContestInputHandler(),
      ),
    );

    // Mirrors home_page.dart: AppSettings lives inside MaterialApp.home, i.e.
    // below the Navigator. A dialog route is a new subtree, so each dialog is
    // re-provided with the existing instance via RepositoryProvider.value.
    // Without that bridge, _KeyBindingsDialogState.initState (and the other two
    // dialogs) reads the provider from the dialog route's own BuildContext and
    // throws ProviderNotFoundException. This test guards that regression.
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<AppSettings>.value(
          value: settings,
          child: BlocProvider<MainSettingsCubit>.value(
            value: MainSettingsCubit(contestManager: contestManager),
            child: const Scaffold(body: OptionsSetting()),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Customize function keys'));
    await tester.pumpAndSettle();
    expect(find.text('Function keys'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Practice seed'));
    await tester.pumpAndSettle();
    expect(find.text('Copy question seed'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review past sessions'));
    await tester.pumpAndSettle();
    expect(find.text('No completed sessions yet.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
}
