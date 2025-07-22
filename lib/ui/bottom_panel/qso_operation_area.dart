import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/operation_event_audio.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/contest_run/key_event_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_cubit.dart';

class QsoOperationAreaCubit extends Cubit<void> {
  final _keyEventHandler = KeyEventManager();

  final AudioPlayer _audioPlayer;
  final AppSettings _appSettings;

  QsoOperationAreaCubit({
    required AppSettings appSettings,
    required AudioPlayer audioPlayer,
  }) : _appSettings = appSettings,
       _audioPlayer = audioPlayer,
       super(null) {
    _keyEventHandler.operationEventStream.listen((event) {
      _handleOperationEvent(event);
    });
  }

  Future<void> _handleOperationEvent(OperationEvent event) async {
    Uint8List? pcmData;

    switch (event) {
      case OperationEvent.cq:
        pcmData = await cqAudioData(_appSettings.stationCallsign);
        break;
      case OperationEvent.exch:
        pcmData = _exchange.isNotEmpty
            ? await exchangeAudioData(_exchange)
            : null;
        break;
      case OperationEvent.tu:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        break;
      case OperationEvent.myCall:
        pcmData = await payloadToAudioData(_appSettings.stationCallsign);
        break;
      case OperationEvent.hisCall:
        pcmData = _hisCall.isNotEmpty
            ? await payloadToAudioData(_hisCall)
            : null;
        break;
      case OperationEvent.b4:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        break;
      case OperationEvent.agn:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/AGN.wav');
        break;
      case OperationEvent.nil:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        break;
    }

    final pcmDataVal = pcmData;
    if (pcmDataVal != null) {
      _audioPlayer.resetAndPlay(pcmDataVal);
    }
  }

  String _hisCall = '';
  String _exchange = '';

  void onCallInput(String callSign) {
    _hisCall = callSign;
  }

  void onExchangeInput(String exchange) {
    _exchange = exchange;
  }

  void onKeyEvent(KeyEvent event) {
    _keyEventHandler.onKeyEvent(event);
  }
}

class QsoOperationArea extends StatelessWidget {
  const QsoOperationArea({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => QsoOperationAreaCubit(
        appSettings: context.read(),
        audioPlayer: context.read(),
      ),
      child: BlocBuilder<QsoOperationAreaCubit, void>(
        builder: (context, _) {
          return Flex(
            direction: Axis.vertical,
            spacing: 15.0,
            children: [
              _QsoInputArea(),
              Expanded(
                flex: 1,
                child: _FunctionKeysPad(
                  onOperationEvent: (event) {
                    // TODO: handle function key event
                  },
                  onInfoIconPressed: () {
                    context.read<MainCubit>().showKeyTips();
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QsoInputArea extends StatelessWidget {
  final _callEditorController = TextEditingController();
  final _exchangeEditorController = TextEditingController();
  final _rstEditorController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final colorSchema = Theme.of(context).colorScheme;
    final bgColor = colorSchema.primaryContainer;

    return BlocConsumer<QsoOperationAreaCubit, void>(
      listener: (context, _) {
        // TODO: implement listener
      },
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Flex(
              direction: Axis.horizontal,
              spacing: 8.0,
              children: [
                Expanded(
                  flex: 1,
                  child: TextField(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Call',
                    ),
                    onChanged: (value) {
                      context.read<QsoOperationAreaCubit>().onCallInput(value);
                    },
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: TextField(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'RST',
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: TextField(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Exchange',
                    ),
                    onChanged: (value) {
                      context.read<QsoOperationAreaCubit>().onExchangeInput(
                        value,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FunctionKeysPad extends StatelessWidget {
  final void Function(OperationEvent event) onOperationEvent;
  final void Function() onInfoIconPressed;

  const _FunctionKeysPad({
    required this.onOperationEvent,
    required this.onInfoIconPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: Axis.horizontal,
      spacing: 16.0,
      children: [
        Expanded(
          flex: 1,
          child: _FunctionKeys(
            onOperationEvent: (event) {
              onOperationEvent(event);
            },
          ),
        ),
        SizedBox(
          width: 56,
          height: 56,
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () {
              onInfoIconPressed();
            },
            icon: Icon(Icons.info_outlined),
          ),
        ),
      ],
    );
  }
}

class _FunctionKeys extends StatelessWidget {
  final void Function(OperationEvent event) onOperationEvent;

  _FunctionKeys({required this.onOperationEvent});

  final _functionKeyBtns = functionKeysMap.entries.map((entry) {
    final buttonTextName = '${entry.key.keyLabel} ${entry.value.btnText}';
    return (buttonTextName, entry.value);
  });

  @override
  Widget build(BuildContext context) {
    final contestManager = context.read<ContestManager>();
    final focusNode = FocusNode(
      onKeyEvent: (node, event) {
        contestManager.onKeyEvent(event);
        return KeyEventResult.handled;
      },
    );

    return Focus(
      focusNode: focusNode,
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 16.0,
        crossAxisSpacing: 16.0,
        childAspectRatio: 2.5,
        children: _functionKeyBtns.map((element) {
          final (text, event) = element;
          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            onPressed: () {
              onOperationEvent(event);
            },
            child: Text(text),
          );
        }).toList(),
      ),
    );
  }
}
