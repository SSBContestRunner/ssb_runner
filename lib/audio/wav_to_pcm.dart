import 'package:flutter/foundation.dart';

Future<Uint8List> wavToPcm(Uint8List wav) async {
  return compute(_wavToPcm, wav);
}

Uint8List _wavToPcm(Uint8List wavData) {
  // 最小WAV文件头长度检查
  if (wavData.lengthInBytes < 44) {
    throw const FormatException("Invalid WAV: File too small");
  }

  // 创建字节数据视图以便读取多字节值
  final byteData = ByteData.sublistView(wavData);
  int offset = 0;

  // 验证RIFF头
  if (String.fromCharCodes(wavData.sublist(0, 4)) != "RIFF") {
    throw const FormatException("Invalid WAV: Missing RIFF header");
  }

  // 验证WAVE格式标识
  if (String.fromCharCodes(wavData.sublist(8, 12)) != "WAVE") {
    throw const FormatException("Invalid WAV: Missing WAVE header");
  }

  offset = 12; // 跳过RIFF头 (12字节)

  // 遍历所有数据块
  while (offset + 8 <= wavData.length) {
    final chunkId = String.fromCharCodes(wavData.sublist(offset, offset + 4));
    final chunkSize = byteData.getUint32(offset + 4, Endian.little);

    // 找到"data"块
    if (chunkId == "data") {
      final dataStart = offset + 8;
      final dataEnd = dataStart + chunkSize;
      
      if (dataEnd > wavData.length) {
        throw const FormatException("Invalid WAV: Corrupted data chunk");
      }
      
      return wavData.sublist(dataStart, dataEnd);
    }
    
    // 跳过当前块并继续查找
    offset += 8 + chunkSize;
  }

  throw const FormatException("PCM data not found in WAV");
}
