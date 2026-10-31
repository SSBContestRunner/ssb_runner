import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/main_page.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
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

  for (final size in const [Size(1280, 720), Size(1024, 650)]) {
    testWidgets(
      'A Console layout fits ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _pumpMainPage(tester, size);

        expect(tester.takeException(), isNull);
        expect(find.text('SSB Runner'), findsWidgets);
        expect(find.byKey(const Key('appBrandMark')), findsOneWidget);
        expect(find.text('CQ WPX'), findsOneWidget);
        expect(find.text('QSO Records'), findsOneWidget);
        expect(find.text('This session'), findsOneWidget);
        expect(find.text('Contest rules'), findsOneWidget);
        expect(find.text('Start training'), findsOneWidget);

        // The topbar and the action row both expose the keyboard reference,
        // including when the action buttons wrap at the minimum width.
        expect(find.byIcon(Icons.keyboard_outlined), findsNWidgets(2));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('A Console layout fits Japanese at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _pumpMainPage(tester, size, locale: const Locale('ja'));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('appBrandMark')), findsOneWidget);
      expect(find.text('CQ WPX'), findsOneWidget);
      expect(find.text('今回の練習'), findsOneWidget);
      expect(find.text('コンテストルール'), findsOneWidget);
      expect(find.text('練習を開始'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpMainPage(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  final database = _createNeverOpenedDatabase();
  final dxccManager = DxccManager(database: database);
  final inputHandler = ContestInputHandler();
  final dataManager = ContestDataManager(
    audioLoader: AudioLoader(),
    audioPlayer: AudioPlayer(),
    appSettings: settings,
    appDatabase: database,
    callsignLoader: CallsignLoader(),
    dxccManager: dxccManager,
    inputHandler: inputHandler,
  );
  final contestManager = ContestManager(contestDataManager: dataManager);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppSettings>.value(value: settings),
          RepositoryProvider<AppDatabase>.value(value: database),
          RepositoryProvider<DxccManager>.value(value: dxccManager),
          RepositoryProvider<ContestManager>.value(value: contestManager),
          RepositoryProvider<ContestTimer>.value(
            value: contestManager.contestTimer,
          ),
          RepositoryProvider<ContestInputHandler>.value(value: inputHandler),
        ],
        child: const Scaffold(body: MainPage()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

AppDatabase? _neverOpenedDatabase;

AppDatabase _createNeverOpenedDatabase() =>
    _neverOpenedDatabase ??= AppDatabase(
      LazyDatabase(
        () async =>
            throw StateError('The layout widgets must not touch the database.'),
      ),
    );
