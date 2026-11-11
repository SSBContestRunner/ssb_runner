/// What happened after the user accepted a crash report.
enum CrashReportOutcome { disabled, created, duplicate, failed }

/// Result of one submission attempt, including the issue URL when the backend
/// returned one.
class CrashSubmission {
  const CrashSubmission({required this.outcome, this.issueUrl});

  final CrashReportOutcome outcome;
  final Uri? issueUrl;
}
