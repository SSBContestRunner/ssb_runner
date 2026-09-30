import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

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
Future<String> diagnosticSummary({int tailLines = 100}) async {
  final location = LogSession.location ?? await resolveLogDirectory();
  final buffer = StringBuffer()
    ..writeln('SSB Runner diagnostic summary')
    ..writeln('generated=${DateTime.now().toUtc().toIso8601String()}');

  for (final line in LogSession.headerLines) {
    buffer.writeln(line);
  }

  final latest = File('${location.path}/latest.log');
  if (latest.existsSync()) {
    final lines = await latest.readAsLines();
    final start = lines.length > tailLines ? lines.length - tailLines : 0;
    buffer.writeln(
      '--- latest.log (last ${lines.length - start} of '
      '${lines.length} lines) ---',
    );
    for (final line in lines.sublist(start)) {
      buffer.writeln(line);
    }
  } else {
    buffer.writeln('--- latest.log not found ---');
  }

  return buffer.toString();
}

/// Zips the log directory plus the diagnostic summary into Documents.
Future<File> exportLogArchive() async {
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
  final documents = await getApplicationDocumentsDirectory();
  final output = File(
    '${documents.path}/ssb-runner-diagnostics-${_timestamp()}.zip',
  );
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
