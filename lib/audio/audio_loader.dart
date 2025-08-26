import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';

// 日本区域实体代码
const List<int> _japan = [339, 177, 192];

// 俄语区实体代码
const List<int> _russianSpeaking = [54, 126, 15, 288, 27, 130, 292];

// 中东区域实体代码
const List<int> middleEast = [
  336,
  378,
  330,
  333,
  348,
  370,
  376,
  391,
  304,
  342,
  384,
  354,
  510,
];

// 南亚区域实体代码
const List<int> _southAsia = [324, 11, 142, 372, 305, 315, 159, 3, 369, 306];

// 东南亚区域实体代码
const List<int> _southeastAsia = [
  387,
  293,
  299,
  46,
  381,
  327,
  375,
  345,
  511,
  312,
  143,
  309,
];

// 英式英语区实体代码
const List<int> _britishEnglish = [
  223,
  279,
  294,
  265,
  114,
  122,
  106,
  150,
  35,
  38,
  147,
  189,
  170,
  34,
  133,
  1,
];

const List<String> _alphabetPhonicLetters = [
  'D',
  'E',
  'G',
  'H',
  'K',
  'O',
  'P',
  'S',
  'T',
];

const myAudioAccentDir = 'Global';

class AudioLoader {
  Future<Uint8List> loadAudio(
    String accentDir,
    AudioPayload audioPayload,
  ) async {
    switch (audioPayload) {
      case CommonPayload():
        return await loadAssetsWavPcmData(
          '$accentDir/Common/${audioPayload.fileName}',
        );
      case CallsignPayload():
        return await _loadCallsign(accentDir, audioPayload);
    }
  }

  Future<Uint8List> _loadCallsign(
    String accentDir,
    CallsignPayload callsignPayload,
  ) async {
    final callsign = callsignPayload.callsign;
    final phonicType = callsignPayload.phonicType;

    final byteBuilder = BytesBuilder();

    for (final char in callsign.characters) {
      final filePath = _charToAudioPath(phonicType, char);
      final pcmData = await loadAssetsWavPcmData(filePath);
      byteBuilder.add(pcmData);
    }

    return byteBuilder.toBytes();
  }

  String _charToAudioPath(PhonicType phonicType, String char) {
    if (char == '/') {
      return 'Number/PORTABLE.wav';
    }

    if (char.isNumber()) {
      return 'Number/${char.toUpperCase()}.wav';
    }

    return '${_obtainPhonicDirByType(phonicType, char)}/${char.toUpperCase()}.wav';
  }

  String _obtainPhonicDirByType(PhonicType phonicType, String char) {
    switch (phonicType) {
      case PhonicType.standard:
        return 'ICAO';
      case PhonicType.location:
        return 'Location';
      case PhonicType.mixed:
        return _obtainRandomPhonicType(char);
    }
  }

  String _obtainRandomPhonicType(String char) {
    final max = (_alphabetPhonicLetters.contains(char)) ? 3 : 2;
    final type = Random(DateTime.now().millisecondsSinceEpoch).nextInt(max);

    switch (type) {
      case 0:
        return 'ICAO';
      case 1:
        return 'Location';
      case 2:
        return 'Alphabet';
      default:
        return 'ICAO';
    }
  }

  String obtainAccentByDxccId(int dxccId) {
    if (_japan.contains(dxccId)) {
      return 'JP';
    } else if (_russianSpeaking.contains(dxccId)) {
      return 'RU';
    } else if (_britishEnglish.contains(dxccId)) {
      return 'UK';
    } else if (_southAsia.contains(dxccId) || _southeastAsia.contains(dxccId)) {
      return 'IN';
    } else {
      return 'US';
    }
  }
}

sealed class AudioPayload {}

class CommonPayload extends AudioPayload {
  final String fileName;

  CommonPayload({required this.fileName});
}

class CallsignPayload extends AudioPayload {
  final String callsign;
  final PhonicType phonicType;

  CallsignPayload({required this.callsign, required this.phonicType});
}

enum PhonicType { standard, location, mixed }
