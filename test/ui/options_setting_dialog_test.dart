import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_settings/main_settings.dart';
import 'package:ssb_runner/ui/main_settings/options_setting.dart';
import 'package:toastification/toastification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Options dialogs can read AppSettings scoped below the Navigator', (
    tester,
  ) async {
    final settings = await _createSettings();

    // Mirrors home_page.dart: AppSettings lives inside MaterialApp.home, i.e.
    // below the Navigator. A dialog route is a new subtree, so each dialog is
    // re-provided with the existing instance via RepositoryProvider.value.
    // Without that bridge, _KeyBindingsDialogState.initState (and the other two
    // dialogs) reads the provider from the dialog route's own BuildContext and
    // throws ProviderNotFoundException. This test guards that regression.
    await _pumpHarness(tester, settings);

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

  testWidgets('Backspace in Duration keeps focus on the Duration field', (
    tester,
  ) async {
    final settings = await _createSettings();
    await _pumpHarness(tester, settings);
    await _focusDuration(tester);

    final durationFocusNode = _durationFocusNode(tester);
    await tester.enterText(find.byType(TextFormField), '60');
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus,
      durationFocusNode,
      reason: 'duration field should stay focused while typing',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus,
      durationFocusNode,
      reason: 'backspace must not move focus away from the duration field',
    );
    expect(_durationText(tester), '6');
  });

  testWidgets('Duration clamps to the max value as soon as it is exceeded', (
    tester,
  ) async {
    final settings = await _createSettings();
    await _pumpHarness(tester, settings);
    await _focusDuration(tester);

    await tester.enterText(find.byType(TextFormField), '999');
    await tester.pump();

    expect(_durationText(tester), '$maxDurationInMinutesPerRun');

    // Let the "max duration" toast auto-close so no timer stays pending.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Emptied Duration stays blank until it loses focus', (
    tester,
  ) async {
    final settings = await _createSettings();
    await _pumpHarness(tester, settings);
    await _focusDuration(tester);

    await tester.enterText(find.byType(TextFormField), '');
    await tester.pump();
    expect(_durationText(tester), isEmpty);

    // Moving focus elsewhere fills the blank box with the stored value.
    await tester.tap(find.byKey(const Key('callsign')));
    await tester.pump();
    expect(_durationText(tester), '0');
  });
}

Future<AppSettings> _createSettings() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  return AppSettings(prefs: prefs);
}

/// Builds a callsign field above the options panel so focus can be moved away
/// from the duration field.
Future<void> _pumpHarness(WidgetTester tester, AppSettings settings) async {
  await tester.pumpWidget(
    ToastificationWrapper(
      child: MaterialApp(
        home: RepositoryProvider<AppSettings>.value(
          value: settings,
          child: BlocProvider<MainSettingsCubit>.value(
            value: MainSettingsCubit(
              contestManager: _createContestManager(settings),
            ),
            child: const Scaffold(
              body: Column(
                children: [
                  TextField(key: Key('callsign')),
                  Expanded(child: OptionsSetting()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Focuses the callsign field first, then the duration field, so Flutter
/// remembers callsign as the previously focused node.
Future<void> _focusDuration(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('callsign')));
  await tester.pump();
  await tester.tap(find.byType(TextFormField));
  await tester.pump();
}

EditableText _durationEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(EditableText),
      ),
    );

FocusNode _durationFocusNode(WidgetTester tester) =>
    _durationEditable(tester).focusNode;

String _durationText(WidgetTester tester) =>
    _durationEditable(tester).controller.text;

ContestManager _createContestManager(AppSettings settings) {
  return ContestManager(
    contestDataManager: ContestDataManager(
      audioLoader: AudioLoader(),
      audioPlayer: AudioPlayer(),
      appSettings: settings,
      appDatabase: _createNeverOpenedDatabase(),
      callsignLoader: CallsignLoader(),
      dxccManager: DxccManager(database: _createNeverOpenedDatabase()),
      inputHandler: ContestInputHandler(),
    ),
  );
}

AppDatabase? _neverOpenedDatabase;

/// None of the settings widgets may touch the database, so a lazy executor
/// keeps the tests free of platform channels and the native sqlite library.
/// The instance is shared so drift does not warn about multiple databases.
AppDatabase _createNeverOpenedDatabase() =>
    _neverOpenedDatabase ??= AppDatabase(
      LazyDatabase(
        () async => throw StateError(
          'The settings widgets must not touch the database.',
        ),
      ),
    );