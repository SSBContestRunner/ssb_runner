import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_settings/main_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Contest and Exchange fill the panel width on separate rows', (
    tester,
  ) async {
    final settings = await _createSettings();
    // ARRL has the longest exchange label
    // ("59 State/Province (W/VE) / 59 Power (DX)").
    settings.contestId = 'ARRL-DX';

    await _pumpSettings(tester, settings);

    // SettingItem pads 14px on each side of the 370px sidebar.
    const contentWidth = 370.0 - 28.0;

    final dropdown = find.byType(DropdownMenu<String>);
    expect(dropdown, findsOneWidget);
    expect(tester.getSize(dropdown).width, contentWidth);

    final exchange = _exchangeField();
    expect(exchange, findsOneWidget);
    expect(tester.getSize(exchange).width, contentWidth);

    // The two fields must be stacked, so the long exchange label gets the whole
    // width instead of being clipped beside the name.
    expect(
      tester.getBottomLeft(dropdown).dy,
      lessThanOrEqualTo(tester.getTopLeft(exchange).dy),
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _exchangeField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Exchange',
);

Future<AppSettings> _createSettings() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  return AppSettings(prefs: prefs);
}

Future<void> _pumpSettings(WidgetTester tester, AppSettings settings) async {
  final database = _createNeverOpenedDatabase();
  final dxccManager = DxccManager(database: database);
  final contestManager = ContestManager(
    contestDataManager: ContestDataManager(
      audioLoader: AudioLoader(),
      audioPlayer: AudioPlayer(),
      appSettings: settings,
      appDatabase: database,
      callsignLoader: CallsignLoader(),
      dxccManager: dxccManager,
      inputHandler: ContestInputHandler(),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppSettings>.value(value: settings),
          RepositoryProvider<DxccManager>.value(value: dxccManager),
          RepositoryProvider<ContestManager>.value(value: contestManager),
        ],
        child: const Scaffold(body: MainSettings()),
      ),
    ),
  );
  // No pumpAndSettle: an idle DropdownMenu keeps a blinking cursor scheduled.
  await tester.pump();
}

AppDatabase? _neverOpenedDatabase;

/// None of the settings widgets may touch the database, so a lazy executor
/// keeps the tests free of platform channels and the native sqlite library.
/// The instance is shared so drift does not warn about multiple databases.
AppDatabase _createNeverOpenedDatabase() =>
    _neverOpenedDatabase ??= AppDatabase(
      drift.LazyDatabase(
        () async => throw StateError(
          'The settings widgets must not touch the database.',
        ),
      ),
    );