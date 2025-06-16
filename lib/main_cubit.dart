// main cubit
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class HomeCubit extends Cubit<bool> {
  HomeCubit() : super(false);

  void onTextChange(String callsign) {
    emit(callsign.isNotEmpty);
  }

  void play(String callsign) async {
    final bufferStream = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
    );

    for (final char in callsign.characters) {
      final path = char.toAudioFilename();
      final filePath = '/Users/wafer-li/Desktop/Global/$path';
      final bytes = await File(filePath).readAsBytes();
      SoLoud.instance.addAudioDataStream(bufferStream, bytes);
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
