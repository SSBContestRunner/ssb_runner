import 'dart:typed_data';

import 'package:worker_manager/worker_manager.dart';

Future<Uint8List> concatUint8List(List<Uint8List> lists) async {
  return workerManager.execute(() => concatUint8ListSync(lists));
}

Uint8List concatUint8ListSync(List<Uint8List> lists) {
  final bytesBuilder = BytesBuilder();

  for (final bytes in lists) {
    bytesBuilder.add(bytes);
  }
  return bytesBuilder.toBytes();
}
