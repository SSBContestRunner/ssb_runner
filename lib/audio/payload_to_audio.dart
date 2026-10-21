import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/wav_to_pcm.dart';
import 'package:ssb_runner/logging/app_logger.dart';

String obtainAssetDir(bool isMe, int dxccId) {
  return isMe ? myAudioAccentDir : obtainAccentByDxccId(dxccId);
}

String obtainRstAudioFileName(bool isMe, {bool isCallsignCorrect = true}) {
  if (isMe) {
    return 'EXCH.wav';
  }

  return isCallsignCorrect ? 'ROGER_YOU_ARE_59.wav' : '5_9.wav';
}

Future<Uint8List> loadAssetsWavPcmData(String filePath) async {
  final bytes = await _loadAssetBytes(filePath);

  if (bytes.isEmpty) {
    return bytes;
  }

  return await wavToPcm(bytes);
}

Future<Uint8List> _loadAssetBytes(String filePath) async {
  try {
    return Uint8List.sublistView(
      await rootBundle.load('assets/voice/$filePath'),
    );
  } on FlutterError catch (error, stackTrace) {
    final fallbackPath = _fallbackAssetPath(filePath);

    if (fallbackPath == null) {
      log.error(
        'audio asset missing',
        tag: 'audio',
        fields: <String, Object?>{'path': filePath},
        error: error,
        stackTrace: stackTrace,
      );
      return Uint8List(0);
    }

    log.warn(
      'audio asset missing, using fallback',
      tag: 'audio',
      fields: <String, Object?>{'path': filePath, 'fallback': fallbackPath},
      error: error,
      stackTrace: stackTrace,
    );

    try {
      return Uint8List.sublistView(
        await rootBundle.load('assets/voice/$fallbackPath'),
      );
    } on FlutterError catch (fallbackError, fallbackStackTrace) {
      log.error(
        'audio asset and fallback missing',
        tag: 'audio',
        fields: <String, Object?>{'path': filePath, 'fallback': fallbackPath},
        error: fallbackError,
        stackTrace: fallbackStackTrace,
      );
      return Uint8List(0);
    }
  }
}

/// Maps a missing accent-specific clip to a fallback clip.
///
/// Common and number clips keep their category and use the neutral `Global`
/// bundle. Letter clips always fall back to ICAO: Location/Alphabet use the
/// same accent's ICAO set so mixed mode keeps the speaker's accent, while a
/// missing ICAO clip uses the Global ICAO set.
String? _fallbackAssetPath(String filePath) {
  final parts = filePath.split('/');

  if (parts.length < 3 || parts.first == 'Global') {
    return null;
  }

  final accent = parts.first;
  final category = parts[1];
  final fileName = parts.sublist(2).join('/');

  switch (category) {
    case 'Common':
    case 'Number':
      return 'Global/$category/$fileName';
    case 'ICAO':
      return 'Global/ICAO/$fileName';
    case 'Location':
    case 'Alphabet':
      return '$accent/ICAO/$fileName';
  }

  return null;
}

RegExp _alpha = RegExp(r'^[a-zA-Z]+$');

extension StringExtension on String {
  bool isNumber() {
    final codeUnit = codeUnitAt(0);
    return codeUnit ^ 0x30 <= 9;
  }

  bool isLetter() {
    return _alpha.hasMatch(this);
  }
}
