import 'dart:convert';

import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/log_source.dart';

/// Reads the in-memory diagnostic buffer installed by the web logging backend.
const LogSource logSource = _MemoryLogSource();

class _MemoryLogSource implements LogSource {
  const _MemoryLogSource();

  @override
  Future<List<String>> latestLogLines() async => log.diagnosticLines;

  @override
  Future<List<LogFileContents>> logFiles() async {
    final lines = log.diagnosticLines;
    return <LogFileContents>[
      LogFileContents(
        name: 'latest.log',
        bytes: utf8.encode(lines.isEmpty ? '' : '${lines.join('\n')}\n'),
      ),
    ];
  }
}
