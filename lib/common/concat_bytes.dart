import 'dart:typed_data';

Uint8List concatUint8List(List<Uint8List> lists) {
  final bytesBuilder = BytesBuilder();

  for (final bytes in lists) {
    bytesBuilder.add(bytes);
  }
  return bytesBuilder.toBytes();
}