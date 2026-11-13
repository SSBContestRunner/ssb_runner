import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/ui/main_page/training_review_overlay.dart';
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

  const cases = [
    (locale: Locale('en'), label: '2 pauses'),
    (locale: Locale('zh'), label: '2 次'),
    (
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      label: '2 次',
    ),
    (
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      label: '2 次',
    ),
    (locale: Locale('ja'), label: '2 回'),
  ];

  for (final item in cases) {
    final language = item.locale.toString();
    testWidgets('暂停格在一行内显示时长与次数 ($language)', (tester) async {
      await _ensureAppFonts();
      final manager = await _pumpOverlay(
        tester,
        item.locale,
        _review(paused: const Duration(minutes: 2, seconds: 14), count: 2),
      );

      // Wall clock 5:00 minus 2:14 paused -> the effective duration is 2:46,
      // so the paused value is unique on screen.
      final pausedValue = find.text('00:02:14');
      expect(pausedValue, findsOneWidget);
      final valueParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: pausedValue, matching: find.byType(RichText)),
      );
      expect(
        _lineCount(valueParagraph, '00:02:14'),
        1,
        reason: 'the paused duration must stay on one line ($language)',
      );

      final count = find.text(item.label);
      expect(count, findsOneWidget);
      final countParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: count, matching: find.byType(RichText)),
      );
      expect(
        _lineCount(countParagraph, item.label),
        1,
        reason: 'the pause count must stay on one line ($language)',
      );

      final cell = find.ancestor(
        of: pausedValue,
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(cell.first).width, 125);

      expect(tester.takeException(), isNull);
      await _tearDown(tester, manager);
    });
  }

  testWidgets('暂停次数为零时不显示暂停格 (en)', (tester) async {
    await _ensureAppFonts();
    final manager = await _pumpOverlay(
      tester,
      const Locale('en'),
      _review(paused: Duration.zero, count: 0),
    );

    final l10n = AppLocalizations.of(
      tester.element(find.byType(TrainingReviewOverlay)),
    );
    expect(find.text(l10n.statPaused), findsNothing);
    expect(find.text('00:05:00'), findsOneWidget);
    final value = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('00:05:00'),
        matching: find.byType(RichText),
      ),
    );
    expect(_lineCount(value, '00:05:00'), 1);

    expect(tester.takeException(), isNull);
    await _tearDown(tester, manager);
  });

  testWidgets('单次暂停的英文标签使用单数 (en)', (tester) async {
    await _ensureAppFonts();
    final manager = await _pumpOverlay(
      tester,
      const Locale('en'),
      _review(paused: const Duration(seconds: 30), count: 1),
    );

    expect(find.text('1 pause'), findsOneWidget);
    expect(find.text('00:00:30'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await _tearDown(tester, manager);
  });
}

/// Counts visual lines. CJK text packed with Latin runs yields one [TextBox]
/// per font run, so boxes are grouped by their vertical offset instead.
int _lineCount(RenderParagraph paragraph, String text) {
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  final tops = <double>[];
  for (final box in boxes) {
    if (tops.every((top) => (top - box.top).abs() > 10)) tops.add(box.top);
  }
  return tops.length;
}

TrainingRunReview _review({required Duration paused, required int count}) =>
    TrainingRunReview(
      metadata: TrainingRunMetadata(
        runId: 'review-run',
        contestId: 'CQ-WPX',
        contestName: 'CQ WPX',
        modeId: 'run',
        difficultyId: 'standard',
        questionSeed: 7,
        audioSeed: 8,
        startedAt: DateTime.utc(2026, 1, 1, 10),
      ),
      endedAt: DateTime.utc(2026, 1, 1, 10, 5),
      qsoCount: 12,
      correctCount: 10,
      callsignErrors: 1,
      exchangeErrors: 1,
      score: 120,
      pauseCount: count,
      pausedDuration: paused,
    );

Future<_ReviewManager> _pumpOverlay(
  WidgetTester tester,
  Locale locale,
  TrainingRunReview review,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1024, 700);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  final database = _neverOpenedDatabase;
  final dataManager = ContestDataManager(
    audioLoader: AudioLoader(),
    audioPlayer: AudioPlayer(),
    appSettings: settings,
    appDatabase: database,
    callsignLoader: CallsignLoader(),
    dxccManager: DxccManager(database: database),
    inputHandler: ContestInputHandler(),
  );
  final manager = _ReviewManager(contestDataManager: dataManager);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepositoryProvider<ContestManager>.value(
        value: manager,
        child: const Scaffold(body: TrainingReviewOverlay()),
      ),
    ),
  );
  await tester.pump();
  manager.emit(review);
  await tester.pump();
  await tester.pump();
  return manager;
}

Future<void> _tearDown(WidgetTester tester, _ReviewManager manager) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  manager.dispose();
}

bool _appFontsLoaded = false;

Future<void> _ensureAppFonts() async {
  if (_appFontsLoaded) return;
  _appFontsLoaded = true;
  await (FontLoader(
    'Iosevka',
  )..addFont(rootBundle.load('fonts/Iosevka-Regular-sub.ttf'))).load();
  await (FontLoader('Noto Sans SC')
        ..addFont(rootBundle.load('fonts/NotoSansSC-Regular-sub.otf'))
        ..addFont(rootBundle.load('fonts/NotoSansSC-Medium-sub.otf'))
        ..addFont(rootBundle.load('fonts/NotoSansSC-Bold-sub.otf')))
      .load();
}

final AppDatabase _neverOpenedDatabase = AppDatabase(
  LazyDatabase(
    () async =>
        throw StateError('The review overlay must not touch the database.'),
  ),
);

class _ReviewManager extends ContestManager {
  _ReviewManager({required super.contestDataManager});

  final _reviews = StreamController<TrainingRunReview>.broadcast();

  @override
  Stream<TrainingRunReview> get reviewStream => _reviews.stream;

  @override
  ContestSessionPhase get sessionPhase => ContestSessionPhase.idle;

  void emit(TrainingRunReview review) => _reviews.add(review);

  void dispose() => _reviews.close();
}
