import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_operation_event_handler.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/settings/settings_issue.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/main_page/key_reference_dialog.dart';
import 'package:ssb_runner/ui/main_page/settings_sheet.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
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
  StreamSubscription<OperationEvent>? _ignoredShortcutSubscription;
  ContestOperationEventHandler? _contestOperationEventHandler;

  final _ignoredShortcutController =
      StreamController<OperationEvent>.broadcast();

  /// Key presses that were recognised but had nothing to do in the current
  /// phase (today only `;`). The input area turns them into a short hint.
  Stream<OperationEvent> get ignoredShortcutStream =>
      _ignoredShortcutController.stream;

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
          _ignoredShortcutSubscription?.cancel();
          _ignoredShortcutSubscription = null;

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
            _ignoredShortcutSubscription = runningManager.ignoredShortcutStream
                .listen((event) {
                  if (!isClosed) _ignoredShortcutController.add(event);
                });
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
    _ignoredShortcutSubscription?.cancel();
    _ignoredShortcutController.close();
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
    final l10n = AppLocalizations.of(context);

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
                _phaseHint(l10n, state),
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
                child: Text(l10n.abandonRound),
              ),
          ],
        );
      },
    );
  }
}

String _phaseHint(AppLocalizations l10n, SingleCallRunState? state) {
  return switch (state) {
    null => '',
    WaitingSubmitCall() => l10n.phaseHintListening,
    HeRepeatCorrectCallAnswer() => l10n.phaseHintCallNotCopied,
    HeAskForExchange() => l10n.phaseHintHeWantsSerial,
    WaitingSubmitMyExchange() => l10n.phaseHintReportSent,
    ReportMyExchange() => l10n.phaseHintSendingReport,
    QsoEnd() => l10n.phaseHintQsoComplete,
    SpListeningCq() => l10n.phaseHintSpListening,
    SpWaitingHisExchange() => l10n.phaseHintSpHeAnswered,
    SpQsoEnd() => l10n.phaseHintSpSigningOff,
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
  // RST is always 59 in this app; it is shown greyed out instead of being
  // filled in by F2.
  final _rstEditorController = TextEditingController(text: '59');
  final _exchangeEditorController = TextEditingController();

  late final Map<int, void Function()> _inputControlMap;

  StreamSubscription<OperationEvent>? _ignoredShortcutSubscription;
  StreamSubscription<ContestSessionPhase>? _sessionPhaseSubscription;

  /// While the run is paused (including the 3-2-1 resume window), both editable
  /// fields become read-only. This is the single gate for text entry: the
  /// controllers keep their drafts, and nothing reaches the input cubit.
  bool _inputLocked = false;

  static bool _locksInput(ContestSessionPhase phase) =>
      phase == ContestSessionPhase.paused ||
      phase == ContestSessionPhase.resuming;

  @override
  void initState() {
    super.initState();
    final contestManager = context.read<ContestManager>();
    _inputLocked = _locksInput(contestManager.sessionPhase);
    _sessionPhaseSubscription = contestManager.sessionPhaseStream.listen((
      phase,
    ) {
      final locked = _locksInput(phase);
      if (!mounted || locked == _inputLocked) {
        return;
      }
      setState(() => _inputLocked = locked);
    });
  }

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

  /// Explains a key press the current phase cannot use (today only `;`), so it
  /// never reads as a dead key or a broken input method.
  void _attachIgnoredShortcutHint() {
    if (_ignoredShortcutSubscription != null) {
      return;
    }

    _ignoredShortcutSubscription = context
        .read<QsoConsoleCubit>()
        .ignoredShortcutStream
        .listen((event) {
          if (!mounted || event != OperationEvent.hisCallAndMyExchange) {
            return;
          }

          toastification.show(
            title: Text(AppLocalizations.of(context).hintNothingToSend),
            type: ToastificationType.info,
            style: ToastificationStyle.fillColored,
            autoCloseDuration: const Duration(seconds: 2),
          );
        });
  }

  void _fillRst() {
    // RST is fixed at 59, so F2 only moves the caret to the received exchange.
    _exchangeFocusNode.requestFocus();
  }

  void _clearInput() {
    _callSignEditorController.clear();
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
    _attachIgnoredShortcutHint();

    return Row(
      spacing: 10,
      children: [
        Expanded(
          flex: 34,
          child: _QsoField(
            fieldKey: const Key('call-field'),
            height: widget.fieldHeight,
            controller: _callSignEditorController,
            focusNode: _callSignFocusNode,
            locked: _inputLocked,
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
          flex: 9,
          child: _QsoField(
            fieldKey: const Key('rst-field'),
            height: widget.fieldHeight,
            controller: _rstEditorController,
            label: l10n.rstLabel,
            readOnly: true,
            focusable: false,
            striped: true,
            fillColor: scheme.surfaceContainerHighest,
            onChanged: null,
          ),
        ),
        Expanded(
          flex: 14,
          child: _SentExchangeField(height: widget.fieldHeight),
        ),
        Expanded(
          flex: 34,
          child: BlocBuilder<_ContestTypeCubit, RegExp?>(
            builder: (context, allowRegex) {
              final allowRegexVal = allowRegex ?? RegExp('[A-Za-z0-9/]');

              return _QsoField(
                fieldKey: const Key('received-exchange-field'),
                height: widget.fieldHeight,
                controller: _exchangeEditorController,
                focusNode: _exchangeFocusNode,
                locked: _inputLocked,
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
    _ignoredShortcutSubscription?.cancel();
    _sessionPhaseSubscription?.cancel();

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
    this.fieldKey,
    this.focusNode,
    this.readOnly = false,
    this.locked = false,
    this.focusable = true,
    this.striped = false,
    this.fillColor,
    this.suffix,
    this.suffixIcon,
    this.inputFormatters,
    this.onChanged,
  });

  final double height;
  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final FocusNode? focusNode;
  final bool readOnly;

  /// Session-level lock (training paused). Unlike [readOnly] this keeps the
  /// enabled styling, so the field does not look broken while it is locked.
  final bool locked;

  /// Read-only projections (RST, sent exchange) must not join the Tab order or
  /// steal focus from the F2 → received-exchange flow.
  final bool focusable;

  /// Fixed-value cells use the prototype's faint diagonal hatch so the
  /// "cannot edit this here" affordance reads before the lock icon is noticed.
  final bool striped;
  final Color? fillColor;
  final String? suffix;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = fillColor ?? scheme.surfaceContainerLowest;
    // The prototype gives fixed cells a stronger outline than editable ones.
    final borderColor = striped
        ? scheme.outline.withValues(alpha: 0.42)
        : scheme.outlineVariant;

    final field = SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (striped)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _DiagonalHatchPainter(
                  background: fill,
                  hatch: scheme.onSurface.withValues(
                    alpha: scheme.brightness == Brightness.dark ? 0.05 : 0.034,
                  ),
                ),
              ),
            ),
          TextField(
            key: fieldKey,
            textInputAction: TextInputAction.none,
            controller: controller,
            focusNode: focusNode,
            readOnly: readOnly || locked,
            canRequestFocus: focusable,
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
              suffixIcon: suffixIcon,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
              suffixStyle: Theme.of(context).textTheme.bodySmall,
              // The striped cell paints its own background so the hatch shows
              // through; the plain cells keep the decorated fill.
              filled: !striped,
              fillColor: striped ? null : fill,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(13, 20, 13, 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary, width: 2),
              ),
              labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
              floatingLabelStyle: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(
                    color: readOnly ? scheme.onSurfaceVariant : scheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    backgroundColor: fill,
                  ),
            ),
          ),
        ],
      ),
    );

    return ExcludeFocus(excluding: !focusable, child: field);
  }
}

/// Faint 45° stripes behind fixed-value cells, matching the prototype's
/// `repeating-linear-gradient(45deg, … 6px, hatch 6px 7px)`.
class _DiagonalHatchPainter extends CustomPainter {
  const _DiagonalHatchPainter({required this.background, required this.hatch});

  final Color background;
  final Color hatch;

  /// 7px spacing measured perpendicular to the stripes = 7·√2 along x.
  static const _step = 9.9;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final paint = Paint()
      ..color = hatch
      ..strokeWidth = 1;
    for (var offset = -size.height; offset < size.width; offset += _step) {
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalHatchPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.hatch != hatch;
}

/// Read-only projection of the operator's own exchange (N1MM's `SentNr`).
/// Its value always points at the next QSO and comes from the same builder as
/// the audio (`ContestManager.myExchangeFor`).
class _SentExchangeField extends StatefulWidget {
  const _SentExchangeField({required this.height});

  final double height;

  @override
  State<_SentExchangeField> createState() => _SentExchangeFieldState();
}

class _SentExchangeFieldState extends State<_SentExchangeField> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = context.read<ContestManager>();
    final settings = context.read<AppSettings>();

    return ValueListenableBuilder<int>(
      valueListenable: settings.settingsRevision,
      builder: (context, _, _) {
        return BlocBuilder<QsoConsoleCubit, SingleCallRunState?>(
          builder: (context, state) {
            // Keep one stable subtree for standby and running: swapping the
            // field out would leave a defunct EditableText listening to the
            // controller while the text is updated during build.
            return BlocBuilder<QsoRecordListCubit, List<QsoResult>>(
              builder: (context, records) {
                final isRunning = state != null;
                // Standby previews the first QSO of the next session; while
                // running the raw row count (DUPE rows included) matches
                // `_myExchange()`.
                final qsoNumber = isRunning ? records.length + 1 : 1;
                return _buildField(
                  l10n,
                  manager.myExchangeFor(qsoNumber),
                  isRunning: isRunning,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildField(
    AppLocalizations l10n,
    String exchange, {
    required bool isRunning,
  }) {
    final display = exchange.isEmpty ? l10n.sentExchangeNotSet : exchange;
    if (_controller.text != display) _controller.text = display;

    return _QsoField(
      fieldKey: const Key('sent-exchange-field'),
      height: widget.height,
      controller: _controller,
      label: l10n.sentExchangeLabel,
      readOnly: true,
      focusable: false,
      striped: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      suffixIcon: _SentExchangeLock(
        isRunning: isRunning,
        onPressed: _openSettings,
      ),
      onChanged: null,
    );
  }

  void _openSettings() {
    // Only reachable on standby: a running session is locked by the settings
    // drawer itself, so the icon is disabled then.
    final settings = context.read<AppSettings>();
    // Follow the effective contest so an armed replay opens the field the
    // upcoming session actually needs.
    final definition = ContestRegistry.byId(settings.effectiveContestId);
    final plan = definition.myExchangePlan(
      stationCallsign: settings.stationCallsign,
      dxccManager: context.read<DxccManager>(),
    );
    final fieldId = plan.sendsSerial || plan.fields.isEmpty
        ? null
        : plan.fields.first.id;

    showSettingsSheet(
      context,
      initialTab: SettingsTab.contestStation,
      focusFieldKey: fieldId == null
          ? null
          : SettingsFocusKeys.exchangeField(fieldId),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _SentExchangeLock extends StatelessWidget {
  const _SentExchangeLock({required this.isRunning, required this.onPressed});

  final bool isRunning;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: isRunning
          ? l10n.sentExchangeLockedRunningTooltip
          : l10n.sentExchangeLockedTooltip,
      child: GestureDetector(
        onTap: isRunning ? null : onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(left: 2, right: 6),
          child: Icon(
            Icons.lock_outline,
            size: 14,
            color: scheme.onSurfaceVariant,
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

  static const _gap = 8.0;

  /// Buttons keep a uniform, breathing-width cell; above this cap a wider
  /// console only adds whitespace instead of stretching each key.
  static const _maxButtonWidth = 280.0;

  /// Width kept free for the pinned keyboard-reference icon.
  static const _keyReferenceWidth = 32.0;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettings>();

    return ValueListenableBuilder<int>(
      valueListenable: settings.functionKeysRevision,
      builder: (context, _, _) {
        final bindings = functionKeysFromSettings(
          settings,
        ).where((binding) => !binding.isSpare).toList();

        // The shortcut icon stays pinned to the right at every width. The
        // buttons share the rest of the row in at most two rows whose item
        // counts differ by one, so the last row never holds a single button
        // while the rows above it are full.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available =
                      constraints.maxWidth - _gap - _keyReferenceWidth;
                  final rows = _balancedRows(bindings);
                  final buttonWidth = _buttonWidth(available, rows);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: _gap,
                    children: [
                      for (final row in rows)
                        Row(
                          spacing: _gap,
                          children: [
                            for (final binding in row)
                              _ActionButton(
                                width: buttonWidth,
                                keyLabel: binding.key.label,
                                action: binding.action!,
                                onPressed: () => onOperationEvent(
                                  operationEventFor(binding.action!),
                                ),
                              ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: _gap),
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

/// Splits the assigned actions into one or two rows. At most five actions share
/// a row, so nine actions become 5 + 4 instead of one long, hard-to-scan row on
/// a wide console; the counts differ by one, so the last row never holds a
/// single button while the rows above it are full.
List<List<FunctionKeyBinding>> _balancedRows(
  List<FunctionKeyBinding> bindings,
) {
  if (bindings.isEmpty) {
    return const [];
  }

  final rowCount = (bindings.length + 4) ~/ 5;
  final perRow = bindings.length ~/ rowCount;
  final extra = bindings.length % rowCount;
  final rows = <List<FunctionKeyBinding>>[];
  var index = 0;

  for (var row = 0; row < rowCount; row++) {
    final take = perRow + (row < extra ? 1 : 0);
    rows.add(bindings.sublist(index, index + take));
    index += take;
  }

  return rows;
}

/// One shared cell width for every row, so the rows line up as a grid. The
/// width is the narrowest cell that still fits the fullest row, capped at
/// [_ActionRow._maxButtonWidth].
double _buttonWidth(double available, List<List<FunctionKeyBinding>> rows) {
  var width = double.infinity;

  for (final row in rows) {
    width = math.min(
      width,
      (available - _ActionRow._gap * (row.length - 1)) / row.length,
    );
  }

  return math.min(width, _ActionRow._maxButtonWidth);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.width,
    required this.keyLabel,
    required this.action,
    required this.onPressed,
  });

  final double width;
  final String keyLabel;
  final OperationAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Tooltip(
      message: l10n.sendTooltip('$keyLabel ${action.label}'),
      child: SizedBox(
        width: width,
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
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Kbd(label: keyLabel),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
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
      height: 20,
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
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
