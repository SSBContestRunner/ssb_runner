import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'export_result.dart';

export 'export_result.dart';

/// Asks for a destination with the system save dialog, then writes [bytes].
///
/// Returns null when the user cancels.
Future<ExportResult?> saveBytes({
  required String suggestedName,
  required List<int> bytes,
  required String fileTypeLabel,
}) async {
  final target = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(label: fileTypeLabel, extensions: const ['zip']),
    ],
  );
  if (target == null) {
    return null;
  }

  await File(target.path).writeAsBytes(bytes, flush: true);
  return ExportResult(displayName: target.path, path: target.path);
}

/// Asks the user for a file and reads it into memory.
///
/// `file_selector`'s open dialog is supported on every target, unlike the save
/// location which the web cannot provide.
Future<PickedFile?> pickFile({
  required String fileTypeLabel,
  required List<String> extensions,
}) async {
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(label: fileTypeLabel, extensions: extensions),
    ],
  );
  if (file == null) {
    return null;
  }

  return PickedFile(name: file.name, bytes: await file.readAsBytes());
}
