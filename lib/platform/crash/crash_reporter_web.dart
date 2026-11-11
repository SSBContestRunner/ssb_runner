import 'dart:convert';
import 'dart:js_interop';

import 'package:catcher_2/model/report.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/crash_payload.dart';
import 'package:ssb_runner/logging/crash_result.dart';
import 'package:web/web.dart' as web;

/// Worker route used by web builds. It is same-origin, so there is no CORS
/// preflight and the page never carries a GitHub token.
const String _proxyUrl = String.fromEnvironment(
  'CRASH_PROXY_URL',
  defaultValue: '/api/crash',
);

/// Whether this build has a crash proxy to talk to.
bool get crashIssueReportingEnabled => _proxyUrl.isNotEmpty;

/// Sends the accepted report to the Cloudflare Worker.
Future<CrashSubmission> submitCrashReport(Report report) async {
  if (_proxyUrl.isEmpty) {
    log.info(
      'crash issue reporting disabled: no proxy url configured',
      tag: 'crash',
    );
    return const CrashSubmission(outcome: CrashReportOutcome.disabled);
  }

  try {
    final payload = await buildWebCrashPayload(report);
    final headers = web.Headers()..set('content-type', 'application/json');
    final request = web.Request(
      _proxyUrl.toJS,
      web.RequestInit(
        method: 'POST',
        headers: headers,
        body: jsonEncode(payload).toJS,
      ),
    );

    final response = await web.window.fetch(request).toDart;
    final text = (await response.text().toDart).toDart;

    if (response.status == 429) {
      log.warn('crash proxy rate limited', tag: 'crash');
      return const CrashSubmission(outcome: CrashReportOutcome.failed);
    }
    if (!response.ok) {
      log.error(
        'crash proxy rejected the report',
        tag: 'crash',
        fields: <String, Object?>{'status': response.status},
      );
      return const CrashSubmission(outcome: CrashReportOutcome.failed);
    }

    if (text.trim().isEmpty) {
      return const CrashSubmission(outcome: CrashReportOutcome.created);
    }

    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      final issueUrl = decoded['issueUrl'];
      return CrashSubmission(
        outcome: decoded['duplicate'] == true
            ? CrashReportOutcome.duplicate
            : CrashReportOutcome.created,
        issueUrl: issueUrl is String ? Uri.tryParse(issueUrl) : null,
      );
    }

    return const CrashSubmission(outcome: CrashReportOutcome.created);
  } catch (error, stackTrace) {
    log.error(
      'crash report submission failed',
      tag: 'crash',
      error: error,
      stackTrace: stackTrace,
    );
    return const CrashSubmission(outcome: CrashReportOutcome.failed);
  }
}
