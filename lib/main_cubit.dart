// main cubit
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_contest_runner/audio/wav_to_pcm.dart';

class HomeCubit extends Cubit<bool> {
  HomeCubit() : super(false);

  void onTextChange(String callsign) {
    emit(callsign.isNotEmpty);
  }

  void play(String callsign) async {
    final bufferStream = SoLoud.instance.setBufferStream(
      channels: Channels.mono,
    );

    for (final char in callsign.characters) {
      final path = char.toAudioFilename();
      final filePath = '/Users/wafer-li/Desktop/Global/$path';
      final bytes = await File(filePath).readAsBytes();

      final pcmData = await wavToPcm(bytes);
      SoLoud.instance.addAudioDataStream(bufferStream, pcmData);
    }

    SoLoud.instance.setDataIsEnded(bufferStream);
    await SoLoud.instance.play(bufferStream);
  }
}

final _regexAlphabet = RegExp(r'[A-Z]');
final _regexNumber = RegExp(r'[0-9]');

extension CharToAudioFilenaem on String {
  String toAudioFilename() {
    final char = toUpperCase();

    String path = '';

    if (_regexAlphabet.hasMatch(char)) {
      path += 'ICAO';
    }

    if (_regexNumber.hasMatch(char)) {
      path += 'Number';
    }

    return '$path/$char.wav';
  }
}
