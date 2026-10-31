import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_operation_event_handler.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/main_page/key_reference_dialog.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

import '../../contest_type/contest_type.dart';

class QsoConsoleCubit extends Cubit<SingleCallRunState?> {
  final ContestInputHandler _inputHandler;

  final ContestManager _contestManager;

  QsoConsoleCubit({
    required ContestManager contestManager,
    required ContestInputHandler contestInputHandler,
  }) : _inputHandler = contestInputHandler,
       _contestManager = contestManager,
       super(null) {
    attachOperationContestRunning();
  }

  StreamSubscription? _inputControlStreamSubscription;
  StreamSubscription? _contestOperationEventHandlerSubscription;
  StreamSubscription<SingleCallRunState>? _contestStateSubscription;
  ContestOperationEventHandler? _contestOperationEventHandler;

  /// Phase guidance is a Beginner-only crutch: at higher difficulties the
  /// operator has to read the band and the state machine themselves.
  bool _showPhaseHint = false;

  bool get showPhaseHint => _showPhaseHint;

  void attachInputControl(void Function(int) callback) {
    if (_inputControlStreamSubscription != null) {
      return;
    }

    _inputControlStreamSubscription = _inputHandler.inputControlStream.listen((
      data,
    ) {
      callback(data);
    });
  }

  void attachOperationContestRunning() {
    _contestOperationEventHandlerSubscription = _contestManager
        .isContestRunningStream
        .listen((isRunning) {
          _contestStateSubscription?.cancel();
          _contestStateSubscription = null;

          final runningManager = _contestManager.contestRunningManager;
          if (isRunning && runningManager != null) {
            _contestOperationEventHandler =
                runningManager.contestOperationEventHandler;
            _showPhaseHint =
                runningManager.difficulty == TrainingDifficulty.beginner;
            // The stream only carries later transitions; seed the hint with the
            // phase the round started in.
            _emitState(runningManager.currentState);
            _contestStateSubscription = runningManager.stateStream.listen(
              _emitState,
            );
          } else {
            _contestOperationEventHandler = null;
            _showPhaseHint = false;
            _emitState(null);
          }
        });
  }

  void _emitState(SingleCallRunState? state) {
    if (isClosed) return;
    emit(state);
  }

  void handleOperationEvent(OperationEvent event) {
    _contestOperationEventHandler?.handleOperationEvent(event);
  }

  void onCallInput(String callsign) {
    _inputHandler.onCallEdit(callsign);
  }

  void onExchangeInput(String exchange) {
    _inputHandler.onExchangeEdit(exchange);
  }

  @override
  Future<void> close() {
    _inputControlStreamSubscription?.cancel();
    _contestOperationEventHandlerSubscription?.cancel();
    _contestStateSubscription?.cancel();
    _contestOperationEventHandler = null;
    return super.close();
  }
}

class QsoConsole extends StatelessWidget {
  const QsoConsole({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => QsoConsoleCubit(
            contestInputHandler: context.read(),
            contestManager: context.read(),
          ),
        ),
        BlocProvider(
          create: (context) =>
              _ContestTypeCubit(contestManager: context.read()),
        ),
      ],
      child: BlocBuilder<QsoConsoleCubit, SingleCallRunState?>(
        // The hint row only appears while a Beginner contest runs; adding/
        // removing it is the only change that alters the layout.
        buildWhen: (previous, current) =>
            (previous == null) != (current == null),
        builder: (context, state) {
          final showHint =
              state != null && context.read<QsoConsoleCubit>().showPhaseHint;
          final isCompact = MediaQuery.sizeOf(context).height <= 700;
          final scheme = Theme.of(context).colorScheme;

          return Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: isCompact
                ? const EdgeInsets.fromLTRB(14, 10, 14, 12)
                : const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showHint) ...[
                  const _PhaseHintBar(),
                  const SizedBox(height: 8),
                ],
                _QsoInputArea(fieldHeight: isCompact ? 58 : 64),
                const SizedBox(height: 12),
                ExcludeFocus(
                  child: _ActionRow(
                    onOperationEvent: (event) {
                      context.read<QsoConsoleCubit>().handleOperationEvent(
                        event,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Beginner-only hint: shows what the round is waiting for and which key moves
/// it on, so a mid-QSO phase (e.g. "he wants his serial") is never a silent
/// dead end. Higher difficulties keep this out of the UI; the transition
/// logging still records the same phase changes.
class _PhaseHintBar extends StatelessWidget {
  const _PhaseHintBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<QsoConsoleCubit, SingleCallRunState?>(
      builder: (context, state) {
        return Row(
          spacing: 8,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_none_outlined,
                size: 16,
                color: scheme.onTertiaryContainer,
              ),
            ),
            Expanded(
              child: Text(
                _phaseHint(state),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
              ),
            ),
            if (_canAbandon(state))
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
                onPressed: () {
                  // Same action as F1: on an in-flight QSO it gives up the
                  // round, otherwise it calls CQ again.
                  context.read<QsoConsoleCubit>().handleOperationEvent(
                    OperationEvent.cq,
                  );
                },
                child: const Text('Abandon (F1)'),
              ),
          ],
        );
      },
    );
  }
}

String _phaseHint(SingleCallRunState? state) {
  return switch (state) {
    null => '',
    WaitingSubmitCall() => 'Listening — copy his call, then Enter',
    HeRepeatCorrectCallAnswer() =>
      'Call not copied — F5 to submit, F7 to repeat',
    HeAskForExchange() =>
      'He wants his serial — type it, Enter to send; F1 abandons this round',
    WaitingSubmitMyExchange() =>
      'Your report is sent — type his serial, then Enter; F5/F7 repeats',
    ReportMyExchange() => 'Sending your report…',
    QsoEnd() => 'QSO complete — starting the next one',
    SpListeningCq() => 'Listening — Enter to pounce, F1 for another CQ',
    SpWaitingHisExchange() =>
      'He answered — copy his serial, then Enter; F5/F7 repeats',
    SpQsoEnd() => 'Signing off — the next CQ follows',
  };
}

bool _canAbandon(SingleCallRunState? state) {
  return switch (state) {
    HeRepeatCorrectCallAnswer() ||
    HeAskForExchange() ||
    WaitingSubmitMyExchange() ||
    ReportMyExchange() => true,
    _ => false,
  };
}

class _QsoInputArea extends StatefulWidget {
  const _QsoInputArea({required this.fieldHeight});

  final double fieldHeight;

  @override
  State<StatefulWidget> createState() {
    return _QsoInputAreaState();
  }
}

class _QsoInputAreaState extends State<_QsoInputArea> {
  final _exchangeFocusNode = FocusNode();
  final _callSignFocusNode = FocusNode();

  final _callSignEditorController = TextEditingController();
  final _rstEditorController = TextEditingController();
  final _exchangeEditorController = TextEditingController();

  late final Map<int, void Function()> _inputControlMap;

  _QsoInputAreaState() {
    _inputControlMap = {
      fillRst: _fillRst,
      clearInput: _clearInput,
      switchCallsignAndExchange: _switchCallsignAndExchange,
    };
  }

  void _attachInputControl(BuildContext context) {
    final cubit = context.read<QsoConsoleCubit>();

    cubit.attachInputControl((inputControl) {
      _inputControlMap[inputControl]?.call();
    });
  }

  void _fillRst() {
    _rstEditorController.text = '59';
    _exchangeFocusNode.requestFocus();
  }

  void _clearInput() {
    _callSignEditorController.clear();
    _rstEditorController.clear();
    _exchangeEditorController.clear();

    _callSignFocusNode.requestFocus();
  }

  void _switchCallsignAndExchange() {
    if (!_callSignFocusNode.hasFocus && !_exchangeFocusNode.hasFocus) {
      return;
    }

    _callSignFocusNode.hasFocus
        ? _fillRst()
        : _callSignFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    _attachInputControl(context);

    return Row(
      spacing: 10,
      children: [
        Expanded(
          flex: 27,
          child: _QsoField(
            height: widget.fieldHeight,
            controller: _callSignEditorController,
            focusNode: _callSignFocusNode,
            label: l10n.callLabel,
            suffix: l10n.autoUppercase,
            inputFormatters: [
              UpperCaseTextFormatter(),
              LengthLimitingTextInputFormatter(maxCallsignLength),
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9/]')),
            ],
            onChanged: (value) {
              context.read<QsoConsoleCubit>().onCallInput(value);
            },
          ),
        ),
        Expanded(
          flex: 12,
          child: _QsoField(
            height: widget.fieldHeight,
            controller: _rstEditorController,
            label: l10n.rstLabel,
            suffix: l10n.autoLabel,
            readOnly: true,
            fillColor: scheme.surfaceContainerHighest,
            onChanged: null,
          ),
        ),
        Expanded(
          flex: 27,
          child: BlocBuilder<_ContestTypeCubit, RegExp?>(
            builder: (context, allowRegex) {
              final allowRegexVal = allowRegex ?? RegExp('[A-Za-z0-9/]');

              return _QsoField(
                height: widget.fieldHeight,
                controller: _exchangeEditorController,
                focusNode: _exchangeFocusNode,
                label: l10n.exchangeFieldLabel,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  FilteringTextInputFormatter.allow(allowRegexVal),
                ],
                onChanged: (value) {
                  context.read<QsoConsoleCubit>().onExchangeInput(value);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _callSignEditorController.dispose();
    _rstEditorController.dispose();
    _exchangeEditorController.dispose();

    _callSignFocusNode.dispose();
    _exchangeFocusNode.dispose();
    super.dispose();
  }
}

class _QsoField extends StatelessWidget {
  const _QsoField({
    required this.height,
    required this.controller,
    required this.label,
    this.focusNode,
    this.readOnly = false,
    this.fillColor,
    this.suffix,
    this.inputFormatters,
    this.onChanged,
  });

  final double height;
  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final bool readOnly;
  final Color? fillColor;
  final String? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: TextField(
        textInputAction: TextInputAction.none,
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: AppDataText.style(
          context,
          fontSize: height <= 58 ? 20 : 22,
          letterSpacing: 1.2,
          color: readOnly ? scheme.onSurfaceVariant : scheme.onSurface,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          suffixStyle: Theme.of(context).textTheme.bodySmall,
          filled: true,
          fillColor: fillColor ?? scheme.surfaceContainerLowest,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(13, 20, 13, 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
          labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
          floatingLabelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            backgroundColor: fillColor ?? scheme.surfaceContainerLowest,
          ),
        ),
      ),
    );
  }
}

class _ContestTypeCubit extends Cubit<RegExp?> {
  final ContestManager _contestManager;
  StreamSubscription<ContestType>? _contestTypeSubscription;

  _ContestTypeCubit({required ContestManager contestManager})
    : _contestManager = contestManager,
      super(null) {
    _contestTypeSubscription = _contestManager.contestTypeStream.listen((
      contestType,
    ) {
      emit(contestType.allowExchangeRegex);
    });
  }

  @override
  Future<void> close() {
    _contestTypeSubscription?.cancel();
    return super.close();
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onOperationEvent});

  final void Function(OperationEvent event) onOperationEvent;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettings>();

    return ValueListenableBuilder<int>(
      valueListenable: settings.functionKeysRevision,
      builder: (context, _, _) {
        final bindings = functionKeysFromSettings(
          settings,
        ).where((binding) => !binding.isSpare).toList();
        final isNarrow = MediaQuery.sizeOf(context).width <= 1060;

        final buttons = [
          for (final binding in bindings)
            _ActionButton(
              keyLabel: binding.key.label,
              action: binding.action!,
              onPressed: () =>
                  onOperationEvent(operationEventFor(binding.action!)),
            ),
        ];

        if (isNarrow) {
          return Wrap(spacing: 6, runSpacing: 8, children: buttons);
        }

        // Wrapping inside the flexible slot keeps a custom 10–12 key layout
        // from overflowing while the default nine stay on one line at 1280.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: buttons)),
            const SizedBox(width: 8),
            _KeyReferenceButton(
              onPressed: () => showKeyReferenceDialog(
                context,
                settings: settings,
                canCustomize: !context.read<ContestManager>().isContestRunning,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.keyLabel,
    required this.action,
    required this.onPressed,
  });

  final String keyLabel;
  final OperationAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Tooltip(
      message: l10n.sendTooltip('$keyLabel ${action.label}'),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.12),
            scheme.surfaceContainerHighest,
          ),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Kbd(label: keyLabel),
                const SizedBox(width: 6),
                Text(
                  action.label,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyReferenceButton extends StatelessWidget {
  const _KeyReferenceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: AppLocalizations.of(context).keyboardReference,
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: onPressed,
        icon: const Icon(Icons.keyboard_outlined),
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: AppDataText.style(
          context,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
