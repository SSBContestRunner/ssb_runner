import 'package:archive/archive.dart';
import 'package:ssb_runner/logging/log_session.dart';
import 'package:ssb_runner/platform/export/export_port.dart';
import 'package:ssb_runner/platform/input/text_input_focus.dart';
import 'package:ssb_runner/platform/logging/log_source_port.dart';

/// Human readable summary that can be pasted into a chat when reporting a bug.
///
/// When [currentSessionOnly] is set, records written by earlier app runs are
/// dropped before the tail is taken. Each run starts with the `# app=` header
/// written by `buildSessionHeader`.
///
/// Startup records are pulled out of the file head first: the tail below is
/// usually too short to reach them, yet they are the first thing needed when
/// diagnosing a blank window.
Future<String> diagnosticSummary({
  int tailLines = 100,
  bool currentSessionOnly = false,
}) async {
  final buffer = StringBuffer()
    ..writeln('SSB Runner diagnostic summary')
    ..writeln('generated=${DateTime.now().toUtc().toIso8601String()}');

  for (final line in LogSession.headerLines) {
    buffer.writeln(line);
  }

  // Live focus facts at export time: a report taken while the app "cannot be
  // typed into" has to say whether the browser still owns the text input.
  final inputSnapshot = inputFocusSnapshot();
  if (inputSnapshot != null) {
    buffer.writeln('input_focus=$inputSnapshot');
  }

  var lines = await logSource.latestLogLines();
  if (currentSessionOnly) {
    lines = _currentSessionLines(lines);
  }

  final startupLines = lines.where(_isStartupLine).toList();
  final startupStart = startupLines.length > _maxStartupLines
      ? startupLines.length - _maxStartupLines
      : 0;
  buffer.writeln('--- startup ---');
  for (final line in startupLines.skip(startupStart)) {
    buffer.writeln(line);
  }

  if (lines.isEmpty) {
    buffer.writeln('--- latest.log not found ---');
  } else {
    final start = lines.length > tailLines ? lines.length - tailLines : 0;
    buffer.writeln(
      '--- latest.log (${currentSessionOnly ? 'current session ' : 'last '}'
      '${lines.length - start} of ${lines.length} lines) ---',
    );
    for (final line in lines.sublist(start)) {
      buffer.writeln(line);
    }
  }

  return buffer.toString();
}

const int _maxStartupLines = 40;

/// Matches the logfmt record written by `AppLogPrinter` for startup tags.
final RegExp _startupLinePattern = RegExp(
  r'^\S+ +[A-Z]+ +(?:boot|env|native) ',
);

bool _isStartupLine(String line) => _startupLinePattern.hasMatch(line);

/// Drops records from previous app runs, including their session headers.
List<String> _currentSessionLines(List<String> lines) {
  final start = lines.lastIndexWhere((line) => line.startsWith('# app='));
  if (start < 0) {
    return lines;
  }

  var bodyStart = start;
  while (bodyStart < lines.length && lines[bodyStart].startsWith('# ')) {
    bodyStart++;
  }
  return lines.sublist(bodyStart);
}

/// Zips the diagnostic summary and the log files into one archive and saves it
/// through the platform save path.
///
/// Returns null when the user cancels; on the web the browser download always
/// starts, so the result only carries the file name.
Future<ExportResult?> exportLogArchive({
  String fileTypeLabel = 'Zip archive',
}) async {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('diagnostic-summary.txt', await diagnosticSummary()),
    );

  for (final file in await logSource.logFiles()) {
    archive.addFile(ArchiveFile.bytes('logs/${file.name}', file.bytes));
  }

  final encoded = ZipEncoder().encode(archive);
  return saveBytes(
    suggestedName: 'ssb-runner-diagnostics-${_timestamp()}.zip',
    bytes: encoded,
    fileTypeLabel: fileTypeLabel,
  );
}

String _timestamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');

  return '${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
}
