import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:catcher_2/model/report_handler.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:ssb_runner/logging/log_session.dart';

/// Fine-grained token injected at build time with
/// `--build-dart-define CRASH_ISSUE_TOKEN=...`.
///
/// It is empty in local builds, which disables the reporter. The token is
/// scoped to this repository only and grants `Issues: Read and write`.
const String _configuredToken = String.fromEnvironment('CRASH_ISSUE_TOKEN');

const String _repositorySlug = 'SSBContestRunner/ssb_runner';
const String _apiHost = 'api.github.com';
const String _apiVersion = '2022-11-28';
const Duration _requestTimeout = Duration(seconds: 15);
const int _maxIssueTitleLength = 240;
const int _maxIssueBodyLength = 60000;
const int _logTailLines = 150;

/// What happened after the user accepted a crash report.
enum CrashReportOutcome { disabled, created, duplicate, failed }

/// Catcher2 handler that files the accepted crash report as a GitHub issue.
///
/// Catcher2 only invokes handlers when the user accepts the report page, so
/// nothing is sent unless the user explicitly confirms.
class CrashIssueReporter extends ReportHandler {
  CrashIssueReporter({this.onResult});

  /// Called after a submission attempt so the UI can show feedback. The
  /// handler never throws into Catcher2, regardless of network failures.
  final void Function(CrashReportOutcome outcome, Uri? issueUrl)? onResult;

  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    if (_configuredToken.isEmpty) {
      log.info(
        'crash issue reporting disabled: no build token configured',
        tag: 'crash',
      );
      _notify(CrashReportOutcome.disabled, null);
      return false;
    }

    try {
      final payload = await buildCrashIssuePayload(report);
      final duplicate = await _findOpenDuplicate(payload.title);

      if (duplicate != null) {
        await _appendComment(duplicate, payload.duplicateComment);
        log.info(
          'crash report appended to existing issue',
          tag: 'crash',
          fields: <String, Object?>{'issue': duplicate.number},
        );
        _notify(CrashReportOutcome.duplicate, duplicate.htmlUrl);
        return true;
      }

      final issueUrl = await _createIssue(payload);
      _notify(CrashReportOutcome.created, issueUrl);
      return true;
    } catch (error, stackTrace) {
      log.error(
        'crash issue submission failed',
        tag: 'crash',
        error: error,
        stackTrace: stackTrace,
      );
      _notify(CrashReportOutcome.failed, null);
      return false;
    }
  }

  @override
  List<PlatformType> getSupportedPlatforms() => PlatformType.values;

  void _notify(CrashReportOutcome outcome, Uri? issueUrl) {
    final callback = onResult;
    if (callback == null) {
      return;
    }

    try {
      callback(outcome, issueUrl);
    } on Object {
      // Feedback must never turn a handled crash into a second failure.
    }
  }

  Future<_ExistingIssue?> _findOpenDuplicate(String title) async {
    final response = await _request(
      'GET',
      Uri.https(_apiHost, '/repos/$_repositorySlug/issues', <String, String>{
        'state': 'open',
        'per_page': '100',
      }),
    );
    if (response is! List) {
      return null;
    }

    for (final item in response) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      // The issues endpoint also returns pull requests.
      if (item.containsKey('pull_request')) {
        continue;
      }

      final number = item['number'];
      if (item['title'] == title && number is int) {
        return _ExistingIssue(
          number: number,
          htmlUrl: _parseUrl(item['html_url']),
        );
      }
    }

    return null;
  }

  Future<Uri?> _createIssue(CrashIssuePayload payload) async {
    final response = await _request(
      'POST',
      Uri.https(_apiHost, '/repos/$_repositorySlug/issues'),
      body: <String, Object?>{'title': payload.title, 'body': payload.body},
    );

    if (response is Map<String, dynamic>) {
      return _parseUrl(response['html_url']);
    }
    return null;
  }

  Future<void> _appendComment(_ExistingIssue issue, String comment) async {
    await _request(
      'POST',
      Uri.https(
        _apiHost,
        '/repos/$_repositorySlug/issues/${issue.number}/comments',
      ),
      body: <String, Object?>{'body': comment},
    );
  }

  Future<Object?> _request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;

    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(_requestTimeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_configuredToken')
        ..set(HttpHeaders.userAgentHeader, 'ssb-runner-crash-reporter')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
        ..set('X-GitHub-Api-Version', _apiVersion);

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(_requestTimeout);
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub API returned ${response.statusCode}: '
          '${_clip(text, 500, suffix: '...')}',
          uri: uri,
        );
      }

      if (text.trim().isEmpty) {
        return null;
      }
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }
}

/// Title/body pair sent to GitHub, plus the short comment used when the crash
/// matches an issue that is already open.
class CrashIssuePayload {
  const CrashIssuePayload({
    required this.title,
    required this.body,
    required this.duplicateComment,
  });

  final String title;
  final String body;
  final String duplicateComment;
}

/// Builds the issue payload from the report and the diagnostics already
/// persisted by the logging pipeline.
Future<CrashIssuePayload> buildCrashIssuePayload(Report report) async {
  final info = await _tryPackageInfo();
  final version = info == null
      ? 'unknown'
      : '${info.version}+${info.buildNumber}';
  final errorType = report.error.runtimeType.toString();
  final platform = report.platformType.name;
  final caughtAt = report.dateTime.toUtc().toIso8601String();

  final title = _clip(
    '[crash] $errorType · $version · $platform · ${_topFrame(report.stackTrace)}',
    _maxIssueTitleLength,
    suffix: '...',
  );

  final header = LogSession.headerLines.isEmpty
      ? 'unavailable'
      : LogSession.headerLines.join('\n');
  final errorText =
      report.error?.toString() ??
      report.errorDetails?.toString() ??
      'unknown error';
  final stackText = report.stackTrace?.toString() ?? 'unavailable';
  final logTail = await diagnosticSummary(tailLines: _logTailLines);

  final body = StringBuffer()
    ..writeln('<!-- generated by the SSB Runner crash reporter -->')
    ..writeln()
    ..writeln('**Platform:** `$platform`')
    ..writeln('**Version:** `$version`')
    ..writeln('**Error type:** `$errorType`')
    ..writeln('**Caught (UTC):** `$caughtAt`')
    ..writeln()
    ..writeln('## Environment')
    ..writeln('```text')
    ..writeln(header)
    ..writeln('```')
    ..writeln()
    ..writeln('## Error')
    ..writeln('```text')
    ..writeln(errorText)
    ..writeln('```')
    ..writeln()
    ..writeln('## Stack trace')
    ..writeln('```text')
    ..writeln(stackText)
    ..writeln('```')
    ..writeln()
    ..writeln('## Log tail')
    ..writeln('```text')
    ..writeln(logTail)
    ..writeln('```');

  return CrashIssuePayload(
    title: title,
    body: _clip(
      body.toString(),
      _maxIssueBodyLength,
      suffix: '\n\n... (truncated)',
    ),
    duplicateComment:
        'Also happened on `$platform` / `$version` at `$caughtAt`.',
  );
}

class _ExistingIssue {
  const _ExistingIssue({required this.number, required this.htmlUrl});

  final int number;
  final Uri? htmlUrl;
}

Future<PackageInfo?> _tryPackageInfo() async {
  try {
    return await PackageInfo.fromPlatform();
  } on Exception {
    return null;
  }
}

/// Extracts the calling symbol from the first stack frame. Line numbers and
/// file paths are left out so issues group by function rather than by build.
String _topFrame(Object? stackTrace) {
  final text = stackTrace?.toString() ?? '';
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#')) {
      continue;
    }

    var frame = trimmed.replaceFirst(RegExp(r'^#\d+\s+'), '');
    final paren = frame.indexOf(' (');
    if (paren > 0) {
      frame = frame.substring(0, paren);
    }
    return _clip(frame, 60, suffix: '...');
  }

  return 'unknown';
}

Uri? _parseUrl(Object? value) {
  if (value is String) {
    return Uri.tryParse(value);
  }
  return null;
}

String _clip(String value, int maxLength, {String suffix = ''}) {
  if (value.length <= maxLength) {
    return value;
  }

  final keep = maxLength - suffix.length;
  return '${value.substring(0, keep < 0 ? 0 : keep)}$suffix';
}
