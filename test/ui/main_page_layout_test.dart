import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/ui/main_page/main_page.dart';
import 'package:ssb_runner/ui/main_page/qso_console.dart';
import 'package:ssb_runner/ui/main_page/qso_log_panel.dart';
import 'package:ssb_runner/ui/main_page/session_panel.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
import 'package:toastification/toastification.dart';
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

  for (final size in const [Size(1280, 720), Size(1024, 700)]) {
    testWidgets(
      'A Console layout fits ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _pumpMainPage(tester, size);

        expect(tester.takeException(), isNull);
        expect(find.text('SSB Runner'), findsWidgets);
        expect(find.byKey(const Key('appBrandMark')), findsOneWidget);
        // The session header and the rules card both name the contest.
        expect(find.text('CQ WPX'), findsWidgets);
        expect(find.text('QSO Records'), findsOneWidget);
        // The console and the log header both name the received exchange.
        expect(find.text('Rcvd'), findsNWidgets(2));
        expect(find.text('Sent'), findsOneWidget);
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
      expect(find.text('CQ WPX'), findsWidgets);
      expect(find.text('今回の練習'), findsOneWidget);
      expect(find.text('コンテストルール'), findsOneWidget);
      expect(find.text('練習を開始'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fixing the gaps flips the chip to ready and clears the badge', (
    tester,
  ) async {
    final settings = await _pumpMainPage(tester, const Size(1280, 720));

    expect(find.text('2 to fix'), findsOneWidget);
    expect(find.byKey(const Key('settingsIssueBadge')), findsOneWidget);

    settings
      ..stationCallsign = 'BI1QJQ'
      ..contestDuration = 30;
    await tester.pump();

    // CQ WPX needs no exchange field, so these two values make it ready.
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('2 to fix'), findsNothing);
    expect(find.byKey(const Key('settingsIssueBadge')), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('start shows a checklist that links into the settings drawer', (
    tester,
  ) async {
    await _pumpMainPage(tester, const Size(1280, 720));

    expect(find.text('2 to fix'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);

    await tester.tap(find.text('Start training'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cannot start yet'), findsOneWidget);
    expect(find.text('Please set station callsign'), findsOneWidget);
    expect(
      find.text('Duration must be set and greater than 0'),
      findsOneWidget,
    );
    expect(
      find.text('Settings › Contest & station › My station'),
      findsOneWidget,
    );
    expect(find.text('Settings › Training'), findsOneWidget);

    // A row is a deep link: the dialog closes and the drawer opens on the tab
    // that owns the field, with the issue shown inline.
    await tester.tap(find.text('Please set station callsign'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cannot start yet'), findsNothing);
    expect(find.text('My station'), findsOneWidget);
    expect(find.text('Please set station callsign'), findsOneWidget);
    expect(find.text('Duration must be set and greater than 0'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the pending chip opens the checklist without pressing start', (
    tester,
  ) async {
    await _pumpMainPage(tester, const Size(1280, 720));

    expect(find.text('2 to fix'), findsOneWidget);
    expect(find.text('Cannot start yet'), findsNothing);

    await tester.tap(find.byKey(const Key('sessionStatusChip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cannot start yet'), findsOneWidget);
    expect(find.text('Please set station callsign'), findsOneWidget);
    expect(
      find.text('Duration must be set and greater than 0'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cannot start yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ready chip is inert and the footer has no banner', (
    tester,
  ) async {
    final settings = await _pumpMainPage(tester, const Size(1280, 720));

    settings
      ..stationCallsign = 'BI1QJQ'
      ..contestDuration = 30;
    await tester.pump();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('2 to fix'), findsNothing);

    // V2: the chip keeps the primary container fill but the check and label
    // use the brand blue, not the darker onPrimaryContainer role.
    final chip = tester.widget<Container>(
      find.byKey(const Key('sessionStatusChip')),
    );
    expect(
      (chip.decoration! as BoxDecoration).color,
      AppTheme.lightScheme.primaryContainer,
    );
    expect(
      tester.widget<Text>(find.text('Ready')).style?.color,
      AppTheme.lightScheme.primary,
    );

    await tester.tap(find.byKey(const Key('sessionStatusChip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cannot start yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an armed replay drives the topbar, rules and sent preview', (
    tester,
  ) async {
    final settings = await _pumpMainPage(tester, const Size(1280, 720));
    settings
      ..contestId = 'CQ-WW-SSB'
      ..stationCallsign = 'BI1QJQ'
      ..contestDuration = 30
      ..setStationExchangeValue('CQ-WW-SSB', 'cqZone', '5');
    await tester.pump();

    settings.armReplay(
      PendingReplay(
        runId: 'wpx-run',
        contestId: 'CQ-WPX',
        contestName: 'CQ WPX',
        modeId: 'run',
        difficultyId: 'standard',
        questionSeed: 42,
        audioSeed: 43,
        armedAtUtc: DateTime.utc(2026, 1, 1, 10, 30),
      ),
    );
    await tester.pump();

    // The ordinary setting is still CQ WW; the whole UI shows the snapshot.
    expect(settings.contestId, 'CQ-WW-SSB');
    expect(find.text('CQ WPX'), findsWidgets);
    expect(find.text('Replay armed'), findsOneWidget);
    expect(
      find.textContaining('You send: 59 + serial number'),
      findsOneWidget,
    );
    expect(find.text('001'), findsOneWidget);

    settings.clearPendingReplay();
    await tester.pump();

    expect(find.text('CQ WW'), findsWidgets);
    expect(find.text('Replay armed'), findsNothing);
    expect(find.text('05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final replayCase in _replayHeaderCases) {
    final language = replayCase.locale.languageCode;

    testWidgets('armed replay header fits 1024x700 ($language)', (
      tester,
    ) async {
      final settings = await _pumpMainPage(
        tester,
        const Size(1024, 700),
        locale: replayCase.locale,
      );
      settings.armReplay(_armedReplay());
      await tester.pump();

      final header = find.byKey(const Key('sessionHeader'));
      final capsule = find.byKey(const Key('replayStatusCapsule'));
      final panel = find.byKey(const Key('replayDetailPanel'));

      // The card reserves no body strip for the replay.
      expect(find.byKey(const Key('replayArmedBanner')), findsNothing);
      expect(
        find.descendant(of: header, matching: find.text(replayCase.mode)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.text(replayCase.difficulty)),
        findsOneWidget,
      );
      expect(find.descendant(of: header, matching: capsule), findsOneWidget);
      _expectNoClippedText(tester, header);

      // The capsule keeps a 48dp tap target.
      expect(tester.getSize(capsule).height, greaterThanOrEqualTo(48));
      expect(find.text(replayCase.startReplay), findsOneWidget);

      // Opening the panel never pushes the timer: the body keeps its place.
      final timerTop = tester.getTopLeft(find.text('00:00:00'));
      await tester.tap(capsule);
      await tester.pump();
      await tester.pump();

      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text(replayCase.panelTitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text(replayCase.cancel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text(replayCase.collapse)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.textContaining(replayCase.armedAt),
        ),
        findsWidgets,
      );
      _expectNoClippedText(tester, panel);
      expect(
        tester.getSize(find.byKey(const Key('replayPanelCancel'))).height,
        48,
      );
      expect(tester.getTopLeft(find.text('00:00:00')), timerTop);

      // The popover is a fixed 320dp card, stays inside the window and keeps
      // its right edge on the capsule instead of filling the overlay.
      final panelRect = tester.getRect(panel);
      final capsuleRect = tester.getRect(capsule);
      expect(panelRect.width, 320);
      expect(panelRect.width, lessThanOrEqualTo(340));
      expect(panelRect.height, lessThanOrEqualTo(440));
      expect(panelRect.height, lessThanOrEqualTo(700 * 0.8));
      expect(panelRect.right, closeTo(capsuleRect.right, 1));
      expect(panelRect.left, greaterThanOrEqualTo(8));
      expect(panelRect.right, lessThanOrEqualTo(1024 - 8));
      expect(panelRect.bottom, lessThanOrEqualTo(700 - 8));

      // "收起" closes the panel and leaves the replay armed.
      await tester.tap(find.byKey(const Key('replayPanelCollapse')));
      await tester.pump();
      expect(panel, findsNothing);
      expect(settings.pendingReplay, isNotNull);

      // Esc closes it too.
      await tester.tap(capsule);
      await tester.pump();
      await tester.pump();
      expect(panel, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(panel, findsNothing);

      // Tapping outside closes it as well. The tap lands on the inert brand
      // mark, away from any text field that consumes outside taps itself.
      await tester.tap(capsule);
      await tester.pump();
      await tester.pump();
      expect(panel, findsOneWidget);
      await tester.tap(find.byKey(const Key('appBrandMark')));
      await tester.pump();
      expect(panel, findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling an armed replay offers an undo ($language)', (
      tester,
    ) async {
      final settings = await _pumpMainPage(
        tester,
        const Size(1024, 700),
        locale: replayCase.locale,
      );
      settings.armReplay(_armedReplay());
      await tester.pump();

      final capsule = find.byKey(const Key('replayStatusCapsule'));
      final panel = find.byKey(const Key('replayDetailPanel'));
      final cancel = find.byKey(const Key('replayPanelCancel'));

      await tester.tap(capsule);
      await tester.pump();
      await tester.pump();
      expect(panel, findsOneWidget);

      // The cancel path is a labelled 48dp button, not an icon-only ✕.
      expect(tester.getSize(cancel).height, 48);
      expect(
        find.descendant(of: panel, matching: find.text(replayCase.cancel)),
        findsOneWidget,
      );

      await tester.tap(cancel);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(settings.pendingReplay, isNull);
      expect(panel, findsNothing);
      expect(capsule, findsNothing);
      expect(find.text(replayCase.startReplay), findsNothing);

      // The toast can undo the cancellation.
      expect(find.text(replayCase.undo), findsOneWidget);
      await tester.tap(find.text(replayCase.undo));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(settings.pendingReplay, isNotNull);
      expect(capsule, findsOneWidget);

      // Let the toast close so no timer stays pending.
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text keeps the replay popover inside 1024x700 '
        '($language)', (tester) async {
      final settings = await _pumpMainPage(
        tester,
        const Size(1024, 700),
        locale: replayCase.locale,
        textScale: 1.5,
      );
      settings.armReplay(_armedReplay());
      await tester.pump();
      expect(tester.takeException(), isNull);

      final capsule = find.byKey(const Key('replayStatusCapsule'));
      final panel = find.byKey(const Key('replayDetailPanel'));
      await tester.tap(capsule);
      await tester.pump();
      await tester.pump();

      expect(panel, findsOneWidget);
      final panelRect = tester.getRect(panel);
      final capsuleRect = tester.getRect(capsule);
      expect(panelRect.width, 320);
      expect(panelRect.width, lessThanOrEqualTo(340));
      expect(panelRect.height, lessThanOrEqualTo(440));
      expect(panelRect.height, lessThanOrEqualTo(700 * 0.8));
      expect(panelRect.right, closeTo(capsuleRect.right, 1));
      expect(panelRect.left, greaterThanOrEqualTo(8));
      expect(panelRect.right, lessThanOrEqualTo(1024 - 8));
      expect(panelRect.top, greaterThanOrEqualTo(0));
      expect(panelRect.bottom, lessThanOrEqualTo(700 - 8));

      // The footer stays pinned while the enlarged details scroll.
      expect(find.byKey(const Key('replayPanelCancel')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('replayPanelCancel'))).height,
        48,
      );
      _expectNoClippedText(tester, panel);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the armed card needs no scrolling at 1024x700 ($language)', (
      tester,
    ) async {
      final settings = await _pumpMainPage(
        tester,
        const Size(1024, 700),
        locale: replayCase.locale,
      );
      settings.armReplay(_armedReplay());
      await tester.pump();

      final card = _sessionCard();
      final cardRect = tester.getRect(card);
      final position = _sessionBodyScroll(tester);

      // The whole body is laid out: nothing is left hidden above the footer.
      expect(position.maxScrollExtent, 0);
      expect(position.pixels, 0);

      // The main button and its status note sit in the footer and are in full
      // view inside the card.
      final button = find.descendant(
        of: card,
        matching: find.byType(FilledButton),
      );
      expect(button, findsOneWidget);
      expect(
        find.descendant(
          of: button,
          matching: find.text(replayCase.startReplay),
        ),
        findsOneWidget,
      );
      final buttonRect = tester.getRect(button);
      expect(buttonRect.top, greaterThanOrEqualTo(cardRect.top));
      expect(buttonRect.bottom, lessThanOrEqualTo(cardRect.bottom));

      final note = find.descendant(
        of: card,
        matching: find.text(replayCase.idleNote),
      );
      expect(note, findsOneWidget);
      final noteRect = tester.getRect(note);
      expect(noteRect.top, greaterThan(buttonRect.bottom));
      expect(noteRect.bottom, lessThanOrEqualTo(cardRect.bottom - 8));
      _expectNoClippedText(tester, button);
      _expectNoClippedText(tester, note);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the timer row fits the card at 1024 ($language)', (
      tester,
    ) async {
      final settings = await _pumpMainPage(
        tester,
        const Size(1024, 700),
        locale: replayCase.locale,
      );
      settings.armReplay(_armedReplay());
      await tester.pump();

      final card = _sessionCard();
      final cardRect = tester.getRect(card);
      expect(cardRect.width, greaterThanOrEqualTo(362));

      for (final key in const [
        Key('timerElapsedLabel'),
        Key('timerRemainingLabel'),
      ]) {
        final label = find.byKey(key);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: label, matching: find.byType(RichText)),
        );
        // No ellipsis: the fixed side column must give the label its full
        // width, with at least 12dp of slack for a longer time value. The
        // paragraph shrink-wraps, so compare its intrinsic width with the
        // width the column offers it.
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph.constraints.maxWidth -
              paragraph.getMaxIntrinsicWidth(double.infinity),
          greaterThanOrEqualTo(12),
        );
        // The label never touches the card's edge: the 20dp padding remains.
        expect(
          cardRect.right - tester.getRect(label).right,
          greaterThanOrEqualTo(8),
        );
      }

      _expectNoClippedText(tester, card);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the replay capsule hover stays inside the 26dp pill', (
    tester,
  ) async {
    final settings = await _pumpMainPage(tester, const Size(1024, 700));
    settings.armReplay(_armedReplay());
    await tester.pump();

    final capsule = find.byKey(const Key('replayStatusCapsule'));
    final pill = find.byKey(const Key('replayStatusCapsulePill'));
    final capsuleRect = tester.getRect(capsule);
    final pillRect = tester.getRect(pill);

    // The 48dp hit band wraps a 26dp visual pill of the same width.
    expect(capsuleRect.height, 48);
    expect(pillRect.height, 26);
    expect(pillRect.width, capsuleRect.width);

    final pillBox = tester.widget<Container>(pill);
    final baseDecoration = pillBox.decoration! as BoxDecoration;
    final baseColor = baseDecoration.color;
    expect(baseDecoration.borderRadius, BorderRadius.circular(8));

    // The InkWell is only the hit target: none of its own ink surfaces may
    // paint over the 48dp band.
    final inkWell = tester.widget<InkWell>(capsule);
    expect(inkWell.hoverColor, Colors.transparent);
    expect(inkWell.highlightColor, Colors.transparent);
    expect(inkWell.splashColor, Colors.transparent);
    expect(inkWell.focusColor, Colors.transparent);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();

    // Hover tint lands on the pill only and does not grow it.
    await mouse.moveTo(tester.getCenter(pill));
    await tester.pump();
    final hoverDecoration =
        tester.widget<Container>(pill).decoration! as BoxDecoration;
    expect(hoverDecoration.color, isNot(baseColor));
    expect(hoverDecoration.borderRadius, BorderRadius.circular(8));
    expect(tester.getSize(pill).height, 26);

    // Leaving the pill restores its fill.
    await mouse.moveTo(const Offset(120, 500));
    await tester.pump();
    expect(
      (tester.widget<Container>(pill).decoration! as BoxDecoration).color,
      baseColor,
    );

    // Pressing uses the same pill rect with a stronger tint.
    await mouse.moveTo(tester.getCenter(pill));
    await mouse.down(tester.getCenter(pill));
    await tester.pump();
    final pressedColor =
        (tester.widget<Container>(pill).decoration! as BoxDecoration).color;
    expect(pressedColor, isNot(baseColor));
    expect(pressedColor, isNot(hoverDecoration.color));
    expect(tester.getSize(pill).height, 26);
    await mouse.up();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('replayDetailPanel')), findsOneWidget);

    // The focus ring is drawn on the pill, and still appears after Esc.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final focusedDecoration =
        tester.widget<Container>(pill).decoration! as BoxDecoration;
    expect(focusedDecoration.border!.top.color, AppTheme.lightScheme.primary);
    expect(tester.getSize(pill).height, 26);

    // Any point inside the 48dp band, including 8dp above the pill, still
    // opens the panel.
    await tester.tapAt(Offset(pillRect.center.dx, pillRect.top - 8));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('replayDetailPanel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the old 650 frame still scrolls the armed session card', (
    tester,
  ) async {
    // window_manager applies the minimum to the window frame on macOS and
    // Windows, so a standard macOS title bar leaves about 622 logical pixels
    // of content at the old 650 frame. That is below the new 700 minimum and
    // the armed card does not fit: the body keeps a hidden remainder.
    for (final locale in const [Locale('zh'), Locale('en'), Locale('ja')]) {
      final settings = await _pumpMainPage(
        tester,
        const Size(1024, 622),
        locale: locale,
      );
      settings.armReplay(_armedReplay());
      await tester.pump();

      expect(
        _sessionBodyScroll(tester).maxScrollExtent,
        greaterThan(0),
        reason: '${locale.languageCode} used to scroll at the old minimum',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the log column keeps its labels at the 1024 minimum', (
    tester,
  ) async {
    for (final locale in const [Locale('en'), Locale('zh'), Locale('ja')]) {
      await _pumpMainPage(tester, const Size(1024, 700), locale: locale);

      // The narrowed log column still leaves the console its full width.
      expect(tester.getRect(find.byType(QsoConsole)).width, 606);
      _expectNoClippedText(tester, find.byType(QsoLogPanel));
      _expectNoClippedText(tester, find.byType(QsoConsole));

      expect(tester.takeException(), isNull);
    }
  });
}

class _ReplayHeaderCase {
  const _ReplayHeaderCase({
    required this.locale,
    required this.mode,
    required this.difficulty,
    required this.startReplay,
    required this.panelTitle,
    required this.cancel,
    required this.collapse,
    required this.undo,
    required this.armedAt,
    required this.idleNote,
  });

  final Locale locale;
  final String mode;
  final String difficulty;
  final String startReplay;
  final String panelTitle;
  final String cancel;
  final String collapse;
  final String undo;
  final String armedAt;
  final String idleNote;
}

const _replayHeaderCases = [
  _ReplayHeaderCase(
    locale: Locale('en'),
    mode: 'S&P',
    difficulty: 'Standard',
    startReplay: 'Start replay',
    panelTitle: 'Replay details',
    cancel: 'Cancel replay',
    collapse: 'Hide',
    undo: 'Undo',
    armedAt: 'Armed at',
    idleNote: 'Stopped · data is kept',
  ),
  _ReplayHeaderCase(
    locale: Locale('zh'),
    mode: '搜索应答',
    difficulty: '标准',
    startReplay: '开始重放',
    panelTitle: '重放详情',
    cancel: '取消重放',
    collapse: '收起',
    undo: '撤销',
    armedAt: '安排于',
    idleNote: '已停止 · 数据会保留',
  ),
  _ReplayHeaderCase(
    locale: Locale('ja'),
    mode: 'S&P',
    difficulty: '標準',
    startReplay: 'リプレイを開始',
    panelTitle: 'リプレイの詳細',
    cancel: 'リプレイをキャンセル',
    collapse: '閉じる',
    undo: '元に戻す',
    armedAt: '予約日時',
    idleNote: '停止中 · データは保持されます',
  ),
];

PendingReplay _armedReplay() => PendingReplay(
  runId: 'wpx-run',
  contestId: 'CQ-WPX',
  contestName: 'CQ WPX',
  modeId: 'search-and-pounce',
  difficultyId: 'standard',
  questionSeed: 42,
  audioSeed: 43,
  armedAtUtc: DateTime.utc(2026, 1, 1, 10, 30),
);

/// Every text inside [scope] must fit on its line: no `…`, no silent clip.
void _expectNoClippedText(WidgetTester tester, Finder scope) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(of: scope, matching: find.byType(RichText)),
  );
  final clipped = paragraphs.where((paragraph) => paragraph.didExceedMaxLines);
  expect(clipped, isEmpty);
}

/// The session card itself (the clipped container around the header).
Finder _sessionCard() => find
    .ancestor(
      of: find.byKey(const Key('sessionHeader')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.clipBehavior == Clip.antiAlias,
      ),
    )
    .first;

/// The scrollable "本次练习" body between the header and the run footer.
ScrollPosition _sessionBodyScroll(WidgetTester tester) {
  final scroller = find.descendant(
    of: find.byType(SessionPanel),
    matching: find.byType(SingleChildScrollView),
  );
  final scrollable = find.descendant(
    of: scroller,
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable).position;
}

Future<AppSettings> _pumpMainPage(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  // Measure with the real faces: the header hides whole items based on these
  // advances, and the Ahem test font would misreport every width.
  await _ensureAppFonts();

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
    ToastificationWrapper(
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return settings;
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

AppDatabase? _neverOpenedDatabase;

AppDatabase _createNeverOpenedDatabase() =>
    _neverOpenedDatabase ??= AppDatabase(
      LazyDatabase(
        () async =>
            throw StateError('The layout widgets must not touch the database.'),
      ),
    );
