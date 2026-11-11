import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:catcher_2/model/report.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/crash_payload.dart';
import 'package:ssb_runner/logging/crash_result.dart';

/// Fine-grained token injected at build time with
/// `--build-dart-define CRASH_ISSUE_TOKEN=...`.
///
/// It is empty in local builds, which disables the reporter. The token is
/// scoped to this repository only and grants `Issues: Read and write`. Desktop
/// builds talk to GitHub directly; web builds use a proxy instead.
const String _configuredToken = String.fromEnvironment('CRASH_ISSUE_TOKEN');

const String _repositorySlug = 'SSBContestRunner/ssb_runner';
const String _apiHost = 'api.github.com';
const String _apiVersion = '2022-11-28';
const Duration _requestTimeout = Duration(seconds: 15);
const List<String> _issueLabels = <String>['crash'];

/// Whether this build can publish crash reports to the issue tracker.
bool get crashIssueReportingEnabled => _configuredToken.isNotEmpty;

/// Files the accepted crash report as a GitHub issue.
Future<CrashSubmission> submitCrashReport(Report report) async {
  if (_configuredToken.isEmpty) {
    log.info(
      'crash issue reporting disabled: no build token configured',
      tag: 'crash',
    );
    return const CrashSubmission(outcome: CrashReportOutcome.disabled);
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
      return CrashSubmission(
        outcome: CrashReportOutcome.duplicate,
        issueUrl: duplicate.htmlUrl,
      );
    }

    final issueUrl = await _createIssue(payload);
    return CrashSubmission(
      outcome: CrashReportOutcome.created,
      issueUrl: issueUrl,
    );
  } catch (error, stackTrace) {
    log.error(
      'crash issue submission failed',
      tag: 'crash',
      error: error,
      stackTrace: stackTrace,
    );
    return const CrashSubmission(outcome: CrashReportOutcome.failed);
  }
}

class _ExistingIssue {
  const _ExistingIssue({required this.number, required this.htmlUrl});

  final int number;
  final Uri? htmlUrl;
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
    body: <String, Object?>{
      'title': payload.title,
      'body': payload.body,
      'labels': _issueLabels,
    },
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
    final request = await client.openUrl(method, uri).timeout(_requestTimeout);
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
