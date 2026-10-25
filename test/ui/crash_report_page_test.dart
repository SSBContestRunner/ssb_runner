import 'package:catcher_2/mode/dialog_report_mode.dart';
import 'package:catcher_2/mode/report_mode_action_confirmed.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/ui/crash_report_page.dart';

void main() {
  test(
    'debug config keeps the dialog mode and release uses the crash page',
    () async {
      final (debugOptions, releaseOptions) = await initErrorHandling();

      expect(debugOptions.reportMode, isA<DialogReportMode>());
      expect(releaseOptions.reportMode, isA<CrashReportMode>());
    },
  );

  testWidgets('shows the crash details and diagnostics actions', (
    tester,
  ) async {
    await _openPage(tester);

    expect(find.text('SSB Runner hit an unexpected error'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Send report'), findsOneWidget);
    expect(find.text('Export logs'), findsOneWidget);
    expect(find.text('Copy diagnostics'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('hides report submission when the build cannot send', (
    tester,
  ) async {
    await _openPage(tester, canSendReport: false);

    expect(find.text('Send report'), findsNothing);
    expect(find.text('Export logs'), findsOneWidget);
    expect(find.text('Copy diagnostics'), findsOneWidget);
  });

  testWidgets('confirming the report closes the page', (tester) async {
    var sent = 0;
    var closed = 0;

    await _openPage(
      tester,
      onSendReport: () => sent++,
      onClose: () => closed++,
    );

    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(sent, 1);
    expect(closed, 0);
    expect(find.text('SSB Runner hit an unexpected error'), findsNothing);
  });

  testWidgets('closing the page rejects the report', (tester) async {
    var sent = 0;
    var closed = 0;

    await _openPage(
      tester,
      onSendReport: () => sent++,
      onClose: () => closed++,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(sent, 0);
    expect(closed, 1);
    expect(find.text('SSB Runner hit an unexpected error'), findsNothing);
  });

  testWidgets('report mode logs the report and opens a single page', (
    tester,
  ) async {
    final action = _RecordingAction();
    final reports = <Report>[];
    final mode = CrashReportMode(canSendReport: true, onReport: reports.add)
      ..reportModeAction = action;

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const Scaffold(body: Text('main'));
          },
        ),
      ),
    );

    mode.requestAction(_report(), context);
    await tester.pumpAndSettle();

    expect(reports, hasLength(1));
    expect(find.text('SSB Runner hit an unexpected error'), findsOneWidget);

    // A second error while the page is visible must still be logged, but it
    // must not stack another page on top.
    mode.requestAction(_report('second'), context);
    await tester.pumpAndSettle();

    expect(reports, hasLength(2));
    expect(find.text('SSB Runner hit an unexpected error'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(action.rejected, 1);
    expect(action.confirmed, 0);
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('report mode confirms the report through Catcher2', (
    tester,
  ) async {
    final action = _RecordingAction();
    final mode = CrashReportMode(canSendReport: true)
      ..reportModeAction = action;

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const Scaffold(body: Text('main'));
          },
        ),
      ),
    );

    mode.requestAction(_report(), context);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(action.confirmed, 1);
    expect(action.rejected, 0);
    expect(find.text('main'), findsOneWidget);
  });
}

Future<void> _openPage(
  WidgetTester tester, {
  bool canSendReport = true,
  VoidCallback? onSendReport,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => CrashReportPage(
                    report: _report(),
                    canSendReport: canSendReport,
                    onSendReport: onSendReport ?? () {},
                    onClose: onClose ?? () {},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Report _report([String message = 'boom']) {
  return Report(
    StateError(message),
    StackTrace.current,
    DateTime.utc(2026, 10, 24),
    const <String, dynamic>{},
    const <String, dynamic>{},
    const <String, dynamic>{},
    null,
    PlatformType.macOS,
    null,
  );
}

class _RecordingAction implements ReportModeAction {
  int confirmed = 0;
  int rejected = 0;

  @override
  void onActionConfirmed(Report report) {
    confirmed++;
  }

  @override
  void onActionRejected(Report report) {
    rejected++;
  }
}
