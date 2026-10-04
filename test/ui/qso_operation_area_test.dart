import 'package:drift/drift.dart';
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
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/bottom_panel/qso_operation_area.dart';
import 'package:ssb_runner/ui/main_page/main_page_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('F1-F8 labels stay fully visible at the minimum window width', (
    tester,
  ) async {
    // At the 1024px minimum window width the QSO operation area is ~346px wide.
    // The function keys used to be laid out by a fixed aspect ratio, which
    // shrank each cell to ~56x23px so the label (e.g. "F1 CQ") was clipped
    // instead of wrapping. The labels must always be fully readable.
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettings(prefs: prefs);
    final database = AppDatabase(
      LazyDatabase(() async => throw StateError('no db')),
    );
    final inputHandler = ContestInputHandler();
    final contestManager = ContestManager(
      contestDataManager: ContestDataManager(
        audioLoader: AudioLoader(),
        audioPlayer: AudioPlayer(),
        appSettings: settings,
        appDatabase: database,
        callsignLoader: CallsignLoader(),
        dxccManager: DxccManager(database: database),
        inputHandler: inputHandler,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<AppSettings>.value(value: settings),
              RepositoryProvider<ContestManager>.value(value: contestManager),
              RepositoryProvider<ContestInputHandler>.value(
                value: inputHandler,
              ),
            ],
            child: BlocProvider<MainPageCubit>(
              create: (_) => MainPageCubit(),
              child: const SizedBox(
                width: 346,
                height: 200,
                child: QsoOperationArea(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), null);

    // The label must not be clipped: the height the paragraph actually got must
    // cover the height it needs to render every wrapped line at that width.
    for (final label in ['F1 CQ', 'F2 EXCH', 'F5 <his>']) {
      expect(find.text(label), findsOneWidget);

      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      final neededHeight = paragraph.getMinIntrinsicHeight(paragraph.size.width);
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(neededHeight - 0.01),
        reason: '"$label" is clipped inside its button',
      );
    }
  });
}