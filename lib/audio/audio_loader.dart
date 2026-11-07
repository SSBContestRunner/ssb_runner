import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/session_random.dart';

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

const myAudioAccentDir = 'Global';

class AudioLoader {
  SessionRandom? _sessionRandom;

  /// The phonic directory actually used per character, keyed by accent,
  /// phonic mode and text. The QSO replay persists these so a mixed-mode
  /// replay repeats the exact letters that were heard.
  final Map<String, List<String>> _resolvedPhonicDirs = {};

  /// Installs the session's question random source so mixed-phonic selection is
  /// reproducible. Cleared when the session ends.
  void setSessionRandom(SessionRandom? random) => _sessionRandom = random;

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
    final dirs = <String>[];

    for (final char in callsign.characters) {
      final dir = _charToPhonicDir(accentDir, phonicType, char);
      dirs.add(dir);
      final filePath = _audioPathForDir(dir, char);
      final audioPath = '$accentDir/$filePath';
      final pcmData = await loadAssetsWavPcmData(audioPath);
      byteBuilder.add(pcmData);
    }

    _resolvedPhonicDirs[_phonicDirsKey(accentDir, callsign, phonicType)] = dirs;

    return byteBuilder.toBytes();
  }

  /// Plays [callsign] with the per-character directories captured during the
  /// session.
  Future<Uint8List> loadCallsignWithDirs(
    String accentDir,
    String callsign,
    List<String> dirs,
  ) async {
    final byteBuilder = BytesBuilder();
    final chars = callsign.characters.toList();

    for (var index = 0; index < chars.length; index++) {
      final char = chars[index];
      final dir = index < dirs.length ? dirs[index] : 'ICAO';
      final filePath = _audioPathForDir(dir, char);
      final pcmData = await loadAssetsWavPcmData('$accentDir/$filePath');
      byteBuilder.add(pcmData);
    }

    return byteBuilder.toBytes();
  }

  /// Resolves (and caches) the per-character phonic directories for [text].
  /// A cache hit returns exactly what was played; a miss resolves now instead
  /// of guessing.
  List<String> resolvePhonicDirs(
    String accentDir,
    String text,
    PhonicType phonicType,
  ) {
    final key = _phonicDirsKey(accentDir, text, phonicType);
    final cached = _resolvedPhonicDirs[key];
    if (cached != null) {
      return cached;
    }

    final dirs = [
      for (final char in text.characters)
        _charToPhonicDir(accentDir, phonicType, char),
    ];
    _resolvedPhonicDirs[key] = dirs;
    return dirs;
  }

  /// Loads the RST clip for a replay.
  ///
  /// The replay always uses `Common/59.wav` (D-04), with an explicit fallback
  /// chain instead of the callsign-correctness heuristic in
  /// [obtainRstAudioFileName].
  Future<Uint8List> loadReplayRstAudio(String accentDir) async {
    final candidates = [
      '$accentDir/Common/59.wav',
      '$accentDir/Common/5_9.wav',
      'US/Common/59.wav',
    ];

    for (final path in candidates) {
      final pcm = await loadExactAssetsWavPcmData(path);
      if (pcm.isNotEmpty) {
        return pcm;
      }
    }

    log.warn(
      'replay RST audio missing, skipping it',
      tag: 'audio.replay',
      fields: <String, Object?>{'accent': accentDir, 'tried': candidates},
    );
    return Uint8List(0);
  }

  String _phonicDirsKey(String accentDir, String text, PhonicType phonicType) =>
      '$accentDir|${phonicType.name}|$text';

  String _charToPhonicDir(String assetDir, PhonicType phonicType, String char) {
    if (char == '/') {
      return 'Common';
    }
    if (char.isNumber()) {
      return 'Number';
    }
    return _obtainPhonicDirByType(assetDir, phonicType, char);
  }

  String _audioPathForDir(String dir, String char) {
    if (dir == 'Common') {
      return 'Common/PORTABLE.wav';
    }
    return '$dir/${char.toUpperCase()}.wav';
  }

  String _obtainPhonicDirByType(
    String assetDir,
    PhonicType phonicType,
    String char,
  ) {
    if (assetDir == myAudioAccentDir) {
      return 'ICAO';
    }

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
    final random = _sessionRandom;
    final type = random != null
        ? random.nextPhonicType(max)
        : Random().nextInt(max);

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
