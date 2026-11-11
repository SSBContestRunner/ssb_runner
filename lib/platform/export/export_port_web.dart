import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:web/web.dart' as web;

import 'export_result.dart';

export 'export_result.dart';

/// Starts a browser download for [bytes].
///
/// `file_selector_web` returns an empty save location, so the file is handed to
/// the browser through a Blob URL instead.
Future<ExportResult?> saveBytes({
  required String suggestedName,
  required List<int> bytes,
  required String fileTypeLabel,
}) async {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob(
    <JSAny>[data.toJS].toJS,
    web.BlobPropertyBag(type: 'application/zip'),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = suggestedName
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  // Revoking immediately can cancel the download in some browsers.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 1), () {
      web.URL.revokeObjectURL(url);
    }),
  );

  return ExportResult(displayName: suggestedName);
}

/// Lets the browser open a file and reads it into memory.
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
