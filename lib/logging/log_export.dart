import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';

import 'log_paths.dart';
import 'log_session.dart';

/// Collects the log files currently stored on disk.
List<File> listLogFiles(String directoryPath) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return const <File>[];
  }

  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return files;
}

/// Human readable summary that can be pasted into a chat when reporting a bug.
///
/// When [currentSessionOnly] is set, records written by earlier app runs are
/// dropped before the tail is taken. Each run starts with the `# app=` header
/// written by `buildSessionHeader`.
Future<String> diagnosticSummary({
  int tailLines = 100,
  bool currentSessionOnly = false,
}) async {
  final location = LogSession.location ?? await resolveLogDirectory();
  final buffer = StringBuffer()
    ..writeln('SSB Runner diagnostic summary')
    ..writeln('generated=${DateTime.now().toUtc().toIso8601String()}');

  for (final line in LogSession.headerLines) {
    buffer.writeln(line);
  }

  final latest = File('${location.path}/latest.log');
  if (latest.existsSync()) {
    var lines = await latest.readAsLines();
    if (currentSessionOnly) {
      lines = _currentSessionLines(lines);
    }
    final start = lines.length > tailLines ? lines.length - tailLines : 0;
    buffer.writeln(
      '--- latest.log (${currentSessionOnly ? 'current session ' : 'last '}'
      '${lines.length - start} of ${lines.length} lines) ---',
    );
    for (final line in lines.sublist(start)) {
      buffer.writeln(line);
    }
  } else {
    buffer.writeln('--- latest.log not found ---');
  }

  return buffer.toString();
}

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

/// Zips the log directory plus the diagnostic summary into the location the
/// user picks in the system save dialog.
///
/// Returns `null` when the user cancels the dialog.
Future<File?> exportLogArchive({String fileTypeLabel = 'Zip archive'}) async {
  final target = await getSaveLocation(
    suggestedName: 'ssb-runner-diagnostics-${_timestamp()}.zip',
    acceptedTypeGroups: [
      XTypeGroup(label: fileTypeLabel, extensions: const ['zip']),
    ],
  );
  if (target == null) {
    return null;
  }

  final location = LogSession.location ?? await resolveLogDirectory();
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('diagnostic-summary.txt', await diagnosticSummary()),
    );

  for (final file in listLogFiles(location.path)) {
    archive.addFile(
      ArchiveFile.bytes('logs/${_fileName(file)}', await file.readAsBytes()),
    );
  }

  final encoded = ZipEncoder().encode(archive);
  final output = File(target.path);
  await output.writeAsBytes(encoded, flush: true);
  return output;
}

String _fileName(File file) => file.uri.pathSegments.last;

String _timestamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');

  return '${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
}
