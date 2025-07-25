import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/contest_run/key_event_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/main.dart';
import 'package:ssb_runner/ui/main_cubit.dart';

const maxCallsignLength = 15;

class QsoOperationAreaCubit extends Cubit<int> {
  final ContestManager _contestManager;

  QsoOperationAreaCubit({required ContestManager contestManager})
    : _contestManager = contestManager,
      super(0);

  bool _isAttachedInputControl = false;

  void attachInputControl(void Function(int) callback) {
    if (_isAttachedInputControl) {
      return;
    }
    _contestManager.inputControlStream.listen((data) {
      callback(data);
    });
    _isAttachedInputControl = true;
  }

  void handleOperationEvent(OperationEvent event) {
    _contestManager.handleOperationEvent(event);
  }

  void onCallInput(String callSign) {
    _contestManager.onCallInput(callSign);
  }

  void onExchangeInput(String exchange) {
    _contestManager.onExchangeInput(exchange);
  }
}

class QsoOperationArea extends StatelessWidget {
  const QsoOperationArea({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          QsoOperationAreaCubit(contestManager: context.read()),
      child: BlocBuilder<QsoOperationAreaCubit, int>(
        buildWhen: (previous, current) => false,
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
                    context.read<QsoOperationAreaCubit>().handleOperationEvent(
                      event,
                    );
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
  final _exchangeFocusonNode = FocusNode();
  final _callSignFocusNode = FocusNode();

  final _callSignEditorController = TextEditingController();
  final _rstEditorController = TextEditingController();
  final _exchangeEditorController = TextEditingController();

  void _attachInputControl(BuildContext context) {
    final cubit = context.read<QsoOperationAreaCubit>();

    cubit.attachInputControl((inputControl) {
      if (inputControl == fillRst) {
        _rstEditorController.text = '59';
        _exchangeFocusonNode.requestFocus();
        return;
      }

      if (inputControl == clearInput) {
        _callSignEditorController.clear();
        _rstEditorController.clear();
        _exchangeEditorController.clear();

        _callSignFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorSchema = Theme.of(context).colorScheme;
    final bgColor = colorSchema.primaryContainer;
    _attachInputControl(context);

    return BlocBuilder<QsoOperationAreaCubit, int>(
      buildWhen: (previous, current) => false,
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
                    controller: _callSignEditorController,
                    focusNode: _callSignFocusNode,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(maxCallsignLength),
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9/]')),
                    ],
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
                    controller: _rstEditorController,
                    readOnly: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'RST',
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _exchangeEditorController,
                    focusNode: _exchangeFocusonNode,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9/]')),
                    ],
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
    return GridView.count(
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
    );
  }
}
