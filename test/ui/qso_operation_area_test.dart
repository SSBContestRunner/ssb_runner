import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/bottom_panel/qso_operation_area.dart';
import 'package:ssb_runner/ui/main_page/main_page_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('F1-F12 labels stay fully visible at the minimum window width', (
    tester,
  ) async {
    // At the 1024px minimum window width the QSO operation area is ~346px wide.
    // The function keys used to be laid out by a fixed aspect ratio, which
    // shrank each cell so the label (e.g. "F1 CQ") was clipped instead of
    // wrapping. All 12 keys now share three rows and must stay fully readable.
    final harness = await _createHarness();
    await _pumpOperationArea(tester, harness);

    expect(tester.takeException(), null);
    expect(find.byType(ElevatedButton), findsNWidgets(12));

    // The label must not be clipped: the height the paragraph actually got must
    // cover the height it needs to render every wrapped line at that width.
    for (final label in [
      'F1 CQ',
      'F2 EXCH',
      'F5 <his>',
      'F6 B4',
      'F8 NIL',
      'F9 Spare',
      'F10 Spare',
      'F11 Spare',
      'F12 Wipe',
    ]) {
      expect(find.text(label), findsOneWidget);

      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      final neededHeight = paragraph.getMinIntrinsicHeight(
        paragraph.size.width,
      );
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(neededHeight - 0.01),
        reason: '"$label" is clipped inside its button',
      );
    }

    // Spare keys are rendered but cannot be pressed.
    for (final label in ['F9 Spare', 'F10 Spare', 'F11 Spare']) {
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, label))
            .onPressed,
        isNull,
        reason: '"$label" must be disabled',
      );
    }
  });

  testWidgets('all Spare settings render twelve disabled Spare buttons', (
    tester,
  ) async {
    final harness = await _createHarness();
    await harness.settings.setFunctionKeyBindings([
      for (final key in FunctionKey.values) FunctionKeyBinding(key, null),
    ]);

    await _pumpOperationArea(tester, harness);

    expect(tester.takeException(), null);
    expect(find.byType(ElevatedButton), findsNWidgets(12));
    for (final key in FunctionKey.values) {
      final label = '${key.label} Spare';
      expect(find.text(label), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, label))
            .onPressed,
        isNull,
      );
    }
    // The default table must not leak back when every key is Spare.
    expect(find.text('F1 CQ'), findsNothing);
  });

  test(
    'the operation area follows the contest lifecycle for mouse clicks',
    () async {
      // Regression: mouse clicks on the on-screen F1-F8 buttons are forwarded to
      // the active contest's operation handler. The cubit never attached to the
      // running state, so the handler stayed null and every click was dropped
      // while the keyboard shortcuts kept working.
      final harness = await _createHarness();
      final manager = _ContestManagerSpy(
        contestDataManager: harness.dataManager,
      );

      final cubit = QsoOperationAreaCubit(
        contestManager: manager,
        contestInputHandler: harness.inputHandler,
      );
      addTearDown(cubit.dispose);

      expect(
        manager.hasRunningListener,
        isTrue,
        reason:
            'without a subscription the clicked operation event has no handler',
      );
    },
  );
}

class _ContestManagerSpy extends ContestManager {
  _ContestManagerSpy({required super.contestDataManager});

  final _runningController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get isContestRunningStream => _runningController.stream;

  bool get hasRunningListener => _runningController.hasListener;
}

typedef _Harness = ({
  AppSettings settings,
  ContestDataManager dataManager,
  ContestInputHandler inputHandler,
});

Future<void> _pumpOperationArea(WidgetTester tester, _Harness harness) async {
  final contestManager = ContestManager(
    contestDataManager: harness.dataManager,
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AppSettings>.value(value: harness.settings),
            RepositoryProvider<ContestManager>.value(value: contestManager),
            RepositoryProvider<ContestInputHandler>.value(
              value: harness.inputHandler,
            ),
          ],
          child: BlocProvider<MainPageCubit>(
            create: (_) => MainPageCubit(),
            child: const SizedBox(
              width: 346,
              height: 280,
              child: QsoOperationArea(),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<_Harness> _createHarness() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  final database = AppDatabase(
    LazyDatabase(() async => throw StateError('no db')),
  );
  final inputHandler = ContestInputHandler();
  final dataManager = ContestDataManager(
    audioLoader: AudioLoader(),
    audioPlayer: AudioPlayer(),
    appSettings: settings,
    appDatabase: database,
    callsignLoader: CallsignLoader(),
    dxccManager: DxccManager(database: database),
    inputHandler: inputHandler,
  );
  return (
    settings: settings,
    dataManager: dataManager,
    inputHandler: inputHandler,
  );
}
