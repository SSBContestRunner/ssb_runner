import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/l10n/app_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_alert_source.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_alert_toaster.dart';
import 'package:toastification/toastification.dart';

const String _blockedTitle = 'The browser blocked audio playback';

Widget _app(WebAudioAlertSource source, {required bool Function() running}) {
  return ToastificationWrapper(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: WebAudioAlertToaster(
          source: source,
          sessionRunning: running,
          phaseChanges: Stream<ContestSessionPhase>.empty(),
        ),
      ),
    ),
  );
}

void main() {
  group('WebAudioAlertAnnouncer', () {
    test('announces a fault that starts while the session runs', () {
      final announcer = WebAudioAlertAnnouncer();

      expect(
        announcer.shouldAnnounce(
          previous: AudioAlertReason.none,
          current: AudioAlertReason.engineDown,
          running: true,
        ),
        isTrue,
      );
    });

    test('never announces outside a running session', () {
      final announcer = WebAudioAlertAnnouncer();

      expect(
        announcer.shouldAnnounce(
          previous: AudioAlertReason.none,
          current: AudioAlertReason.engineDown,
          running: false,
        ),
        isFalse,
      );
    });

    test('recovery clears the allowance, so a relapse announces again', () {
      final announcer = WebAudioAlertAnnouncer();
      bool edge(AudioAlertReason previous, AudioAlertReason current) {
        return announcer.shouldAnnounce(
          previous: previous,
          current: current,
          running: true,
        );
      }

      expect(edge(AudioAlertReason.none, AudioAlertReason.engineDown), isTrue);
      expect(edge(AudioAlertReason.engineDown, AudioAlertReason.none), isFalse);
      expect(edge(AudioAlertReason.none, AudioAlertReason.engineDown), isTrue);
    });

    test('a new session starts with a fresh allowance', () {
      final announcer = WebAudioAlertAnnouncer();
      announcer.shouldAnnounce(
        previous: AudioAlertReason.none,
        current: AudioAlertReason.engineDown,
        running: true,
      );

      announcer.reset();

      expect(
        announcer.shouldAnnounce(
          previous: AudioAlertReason.none,
          current: AudioAlertReason.engineDown,
          running: true,
        ),
        isTrue,
      );
    });
  });

  group('WebAudioAlertToaster', () {
    testWidgets('stays quiet outside a running session', (tester) async {
      final source = _FakeSource();
      addTearDown(source.snapshot.dispose);

      await tester.pumpWidget(_app(source, running: () => false));
      source.snapshot.value = const AudioMonitorSnapshot(
        reason: AudioAlertReason.engineDown,
      );
      await tester.pump();

      expect(find.text(_blockedTitle), findsNothing);
    });

    testWidgets('warns once when the engine fails during a run', (
      tester,
    ) async {
      final source = _FakeSource();
      addTearDown(source.snapshot.dispose);

      await tester.pumpWidget(_app(source, running: () => true));
      source.snapshot.value = const AudioMonitorSnapshot(
        reason: AudioAlertReason.engineDown,
      );
      await tester.pumpAndSettle();

      expect(find.text(_blockedTitle), findsOneWidget);

      // Let the toast's auto-close timer drain before the tree is torn down.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}

class _FakeSource implements WebAudioAlertSource {
  @override
  final ValueNotifier<AudioMonitorSnapshot> snapshot =
      ValueNotifier<AudioMonitorSnapshot>(AudioMonitorSnapshot.initial);

  @override
  Future<bool> retry() async => true;
}
