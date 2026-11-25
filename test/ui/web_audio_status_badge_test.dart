import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/l10n/app_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_alert_source.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_status_badge.dart';
import 'package:toastification/toastification.dart';

const String _blockedTitle = 'The browser blocked audio playback';
const String _hint =
    'Browsers cannot detect system volume; if you still hear nothing, '
    'check whether the system or this browser is muted.';
const String _unavailable =
    'Audio is unavailable in this browser. Training continues without sound.';

Widget _app(WebAudioAlertSource source) {
  return ToastificationWrapper(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: WebAudioStatusBadge(source: source)),
      ),
    ),
  );
}

void main() {
  testWidgets('a healthy engine shows no badge', (tester) async {
    final source = _FakeSource();
    addTearDown(source.snapshot.dispose);

    await tester.pumpWidget(_app(source));

    expect(find.byKey(const Key('audioStatusBadge')), findsNothing);
  });

  testWidgets('an engine fault inserts the badge', (tester) async {
    final source = _FakeSource();
    addTearDown(source.snapshot.dispose);

    await tester.pumpWidget(_app(source));
    source.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.engineDown,
    );
    await tester.pump();

    expect(find.byKey(const Key('audioStatusBadge')), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    expect(find.byTooltip(_blockedTitle), findsOneWidget);
  });

  testWidgets('the badge opens the explanation dialog', (tester) async {
    final source = _FakeSource();
    addTearDown(source.snapshot.dispose);

    await tester.pumpWidget(_app(source));
    source.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.engineDown,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('audioStatusBadge')));
    await tester.pumpAndSettle();

    expect(find.text(_blockedTitle), findsOneWidget);
    expect(find.text(_hint), findsOneWidget);
    expect(find.text('Enable sound'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('enabling sound retries and closes the dialog on success', (
    tester,
  ) async {
    final source = _FakeSource();
    addTearDown(source.snapshot.dispose);

    await tester.pumpWidget(_app(source));
    source.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.engineDown,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('audioStatusBadge')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webAudioEnableAudio')));
    await tester.pumpAndSettle();

    expect(source.retryCalls, 1);
    expect(find.text(_hint), findsNothing);
    expect(find.byKey(const Key('audioStatusBadge')), findsNothing);
  });

  testWidgets('a retry in flight disables the enable button', (tester) async {
    final source = _FakeSource();
    addTearDown(source.snapshot.dispose);
    source.gate = Completer<bool>();

    await tester.pumpWidget(_app(source));
    source.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.engineDown,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('audioStatusBadge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webAudioEnableAudio')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('webAudioEnableAudio')),
    );
    expect(button.onPressed, isNull);

    source.gate!.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('a failed retry keeps the dialog and warns once', (tester) async {
    final source = _FakeSource()..result = false;
    addTearDown(source.snapshot.dispose);

    await tester.pumpWidget(_app(source));
    source.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.engineDown,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('audioStatusBadge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webAudioEnableAudio')));
    await tester.pumpAndSettle();

    expect(find.text(_hint), findsOneWidget);
    expect(find.text(_unavailable), findsOneWidget);
    expect(find.byKey(const Key('audioStatusBadge')), findsOneWidget);

    // Let the toast's auto-close timer drain before the tree is torn down.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

class _FakeSource implements WebAudioAlertSource {
  @override
  final ValueNotifier<AudioMonitorSnapshot> snapshot =
      ValueNotifier<AudioMonitorSnapshot>(AudioMonitorSnapshot.initial);

  bool result = true;
  int retryCalls = 0;
  Completer<bool>? gate;

  @override
  Future<bool> retry() async {
    retryCalls++;
    final gate = this.gate;
    final recovered = gate != null ? await gate.future : result;
    if (recovered) snapshot.value = AudioMonitorSnapshot.initial;
    return recovered;
  }
}
