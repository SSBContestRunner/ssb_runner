import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/main_settings/main_settings.dart';
import 'package:toastification/toastification.dart';

class _Options {
  const _Options({
    required this.mode,
    required this.duration,
    required this.phonicType,
    required this.incomingAccent,
    required this.difficulty,
    required this.volume,
  });
  final TrainingMode mode;
  final int duration;
  final PhonicType phonicType;
  final IncomingAccent incomingAccent;
  final TrainingDifficulty difficulty;
  final double volume;
}

class _OptionsCubit extends Cubit<_Options> {
  _OptionsCubit(this._settings)
    : super(
        _Options(
          mode: TrainingMode.fromId(_settings.contestModeId),
          duration: _settings.contestDuration,
          phonicType: _settings.phonicType,
          incomingAccent: _settings.incomingAccent,
          difficulty: _settings.difficulty,
          volume: _settings.audioVolume,
        ),
      ) {
    durationController = TextEditingController(text: state.duration.toString());
    durationFocusNode = FocusNode()..addListener(_handleDurationFocusChange);
  }

  final AppSettings _settings;

  // Owned by the cubit so the field widget stays stateless while keeping its
  // editing state and focus stable across rebuilds.
  late final TextEditingController durationController;
  late final FocusNode durationFocusNode;

  void _handleDurationFocusChange() {
    if (durationFocusNode.hasFocus) return;
    // An empty box stays empty while it has focus; only fall back to the stored
    // value once focus leaves, so the field never displays a blank duration.
    if (durationController.text.isEmpty) {
      durationController.text = state.duration.toString();
    }
  }

  void setMode(TrainingMode? value) {
    if (value != null) {
      _settings.contestModeId = value.id;
      _emit(mode: value);
    }
  }

  void setDifficulty(TrainingDifficulty? value) {
    if (value != null) {
      _settings.difficulty = value;
      _emit(difficulty: value);
    }
  }

  void setDuration(String input, AppLocalizations l10n) {
    final parsed = int.tryParse(input);
    if (parsed != null && parsed > maxDurationInMinutesPerRun) {
      toastification.show(
        title: Text(l10n.maxDurationWarning(maxDurationInMinutesPerRun)),
        autoCloseDuration: const Duration(seconds: 2),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
      );
    }
    final value = (parsed ?? 0).clamp(0, maxDurationInMinutesPerRun).toInt();
    _settings.contestDuration = value;
    _emit(duration: value);

    // Show the clamped value immediately, e.g. typing 999 becomes 120.
    if (parsed != null && parsed > maxDurationInMinutesPerRun) {
      final text = value.toString();
      durationController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void setPhonic(PhonicType? value) {
    if (value != null) {
      _settings.phonicType = value;
      _emit(phonicType: value);
    }
  }

  void setIncomingAccent(IncomingAccent? value) {
    if (value != null) {
      _settings.incomingAccent = value;
      _emit(incomingAccent: value);
    }
  }

  void setVolume(double value) {
    _settings.audioVolume = value;
    _emit(volume: value);
  }

  @override
  Future<void> close() {
    durationFocusNode
      ..removeListener(_handleDurationFocusChange)
      ..dispose();
    durationController.dispose();
    return super.close();
  }

  void _emit({
    TrainingMode? mode,
    int? duration,
    PhonicType? phonicType,
    IncomingAccent? incomingAccent,
    TrainingDifficulty? difficulty,
    double? volume,
  }) => emit(
    _Options(
      mode: mode ?? state.mode,
      duration: duration ?? state.duration,
      phonicType: phonicType ?? state.phonicType,
      incomingAccent: incomingAccent ?? state.incomingAccent,
      difficulty: difficulty ?? state.difficulty,
      volume: volume ?? state.volume,
    ),
  );
}

class OptionsSetting extends StatelessWidget {
  const OptionsSetting({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => _OptionsCubit(context.read()),
    child: BlocBuilder<_OptionsCubit, _Options>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context);
        final enabled = !context.watch<MainSettingsCubit>().state;
        final cubit = context.read<_OptionsCubit>();
        final settings = context.read<AppSettings>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<AppLanguage>(
              valueListenable: settings.languageNotifier,
              builder: (context, language, _) => Semantics(
                label: l10n.language,
                child: DropdownMenu<AppLanguage>(
                  enabled: enabled,
                  expandedInsets: EdgeInsets.zero,
                  initialSelection: language,
                  label: Text(l10n.language),
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: AppLanguage.auto,
                      label: l10n.languageAuto,
                    ),
                    DropdownMenuEntry(
                      value: AppLanguage.english,
                      label: l10n.languageEnglish,
                    ),
                    DropdownMenuEntry(
                      value: AppLanguage.simplifiedChinese,
                      label: l10n.languageSimplifiedChinese,
                    ),
                    DropdownMenuEntry(
                      value: AppLanguage.traditionalChinese,
                      label: l10n.languageTraditionalChinese,
                    ),
                    DropdownMenuEntry(
                      value: AppLanguage.japanese,
                      label: l10n.languageJapanese,
                    ),
                  ],
                  onSelected: (value) {
                    if (value != null) settings.language = value;
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _menu<TrainingMode>(
                    enabled: enabled,
                    label: l10n.trainingModeFieldLabel,
                    value: state.mode,
                    entries: TrainingMode.values
                        .map(
                          (it) => DropdownMenuEntry(
                            value: it,
                            label: l10n.trainingModeLabel(it),
                          ),
                        )
                        .toList(),
                    onSelected: cubit.setMode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    label: l10n.practiceDurationSemantics,
                    child: TextFormField(
                      enabled: enabled,
                      controller: cubit.durationController,
                      focusNode: cubit.durationFocusNode,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      keyboardType: TextInputType.number,
                      onChanged: (value) => cubit.setDuration(value, l10n),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: l10n.durationLabel,
                        suffixText: l10n.durationUnit,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _menu<TrainingDifficulty>(
              enabled: enabled,
              label: l10n.difficultyFieldLabel,
              value: state.difficulty,
              entries: TrainingDifficulty.values
                  .map(
                    (it) => DropdownMenuEntry(
                      value: it,
                      label: l10n.trainingDifficultyLabel(it),
                    ),
                  )
                  .toList(),
              onSelected: cubit.setDifficulty,
            ),
            const SizedBox(height: 12),
            _menu<PhonicType>(
              enabled: enabled,
              label: l10n.phonicTypeFieldLabel,
              value: state.phonicType,
              entries: [
                DropdownMenuEntry(
                  value: PhonicType.standard,
                  label: l10n.phonicStandard,
                ),
                DropdownMenuEntry(
                  value: PhonicType.location,
                  label: l10n.phonicLocation,
                ),
                DropdownMenuEntry(
                  value: PhonicType.mixed,
                  label: l10n.phonicMixed,
                ),
              ],
              onSelected: cubit.setPhonic,
            ),
            const SizedBox(height: 12),
            _menu<IncomingAccent>(
              enabled: enabled,
              label: l10n.incomingAccentFieldLabel,
              value: state.incomingAccent,
              entries: IncomingAccent.values
                  .map(
                    (it) => DropdownMenuEntry(
                      value: it,
                      label: l10n.incomingAccentLabel(it),
                    ),
                  )
                  .toList(),
              onSelected: cubit.setIncomingAccent,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.incomingAccentAutoHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Semantics(
              label: l10n.volumeSemantics,
              value: l10n.volumeValue((state.volume * 100).round()),
              child: Slider(
                value: state.volume,
                min: 0.2,
                max: 1.2,
                divisions: 10,
                label: l10n.volumeLabel((state.volume * 100).round()),
                onChanged: enabled ? cubit.setVolume : null,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled
                    ? () => showDialog<void>(
                        context: context,
                        builder: (_) => RepositoryProvider<AppSettings>.value(
                          value: settings,
                          child: const _KeyBindingsDialog(),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.keyboard_outlined),
                label: Text(l10n.customizeFunctionKeys),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled
                    ? () => showDialog<void>(
                        context: context,
                        builder: (_) => RepositoryProvider<AppSettings>.value(
                          value: settings,
                          child: const _PracticeSeedDialog(),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.casino_outlined),
                label: Text(
                  settings.practiceSeedSummary.isEmpty
                      ? l10n.practiceSeed
                      : l10n.practiceSeedWithSummary(
                          settings.practiceSeedSummary,
                        ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => RepositoryProvider<AppSettings>.value(
                    value: settings,
                    child: const _SessionHistoryDialog(),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: Text(l10n.reviewPastSessions),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _menu<T>({
    required bool enabled,
    required String label,
    required T value,
    required List<DropdownMenuEntry<T>> entries,
    required void Function(T?) onSelected,
  }) => Semantics(
    label: label,
    child: DropdownMenu<T>(
      enabled: enabled,
      expandedInsets: EdgeInsets.zero,
      initialSelection: value,
      label: Text(label),
      dropdownMenuEntries: entries,
      onSelected: onSelected,
    ),
  );
}

class _KeyBindingsDialog extends StatefulWidget {
  const _KeyBindingsDialog();

  @override
  State<_KeyBindingsDialog> createState() => _KeyBindingsDialogState();
}

class _KeyBindingsDialogState extends State<_KeyBindingsDialog> {
  late final AppSettings settings;
  late final Map<OperationAction, String> bindings;

  @override
  void initState() {
    super.initState();
    settings = context.read();
    bindings = {
      for (final action in OperationAction.values)
        action: settings.binding(action),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.functionKeysTitle),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final action in OperationAction.values)
              DropdownButtonFormField<String>(
                initialValue: bindings[action],
                decoration: InputDecoration(labelText: action.label),
                items: List.generate(
                  8,
                  (index) => DropdownMenuItem(
                    value: 'F${index + 1}',
                    child: Text('F${index + 1}'),
                  ),
                ),
                onChanged: (key) {
                  if (key != null) setState(() => bindings[action] = key);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (bindings.values.toSet().length != bindings.length) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.functionKeysUnique)));
              return;
            }
            for (final entry in bindings.entries) {
              settings.setBinding(entry.key, entry.value);
            }
            Navigator.pop(context);
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _PracticeSeedDialog extends StatefulWidget {
  const _PracticeSeedDialog();

  @override
  State<_PracticeSeedDialog> createState() => _PracticeSeedDialogState();
}

class _PracticeSeedDialogState extends State<_PracticeSeedDialog> {
  late final AppSettings settings;
  late final TextEditingController questionController;
  late final TextEditingController audioController;
  late bool lockQuestion;
  late bool lockAudio;

  @override
  void initState() {
    super.initState();
    settings = context.read();
    questionController = TextEditingController(
      text: settings.questionSeed?.toString() ?? '',
    );
    audioController = TextEditingController(
      text: settings.audioSeed?.toString() ?? '',
    );
    lockQuestion = settings.lockQuestionSeed;
    lockAudio = settings.lockAudioSeed;
  }

  @override
  void dispose() {
    questionController.dispose();
    audioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.practiceSeed),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: l10n.questionSeedLabel,
                child: TextField(
                  controller: questionController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: l10n.questionSeedLabel,
                    helperText: l10n.questionSeedHelper,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.lockQuestionSeed),
                subtitle: Text(l10n.lockQuestionSeedSubtitle),
                value: lockQuestion,
                onChanged: (value) => setState(() => lockQuestion = value),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: l10n.audioSeedLabel,
                child: TextField(
                  controller: audioController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: l10n.audioSeedLabel,
                    helperText: l10n.audioSeedHelper,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.lockAudioSeed),
                subtitle: Text(l10n.lockAudioSeedSubtitle),
                value: lockAudio,
                onChanged: (value) => setState(() => lockAudio = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final value = questionController.text.trim();
            if (value.isEmpty) {
              return;
            }
            await Clipboard.setData(ClipboardData(text: value));
          },
          child: Text(l10n.copyQuestionSeed),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final question = int.tryParse(questionController.text.trim());
            final audio = int.tryParse(audioController.text.trim());
            settings
              ..lockQuestionSeed = lockQuestion
              ..lockAudioSeed = lockAudio
              ..questionSeed = question
              ..audioSeed = audio
              ..pendingQuestionSeed = question
              ..pendingAudioSeed = audio;
            Navigator.pop(context);
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _SessionHistoryDialog extends StatelessWidget {
  const _SessionHistoryDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessions = context.read<AppSettings>().sessionHistory;
    return AlertDialog(
      title: Text(l10n.pastSessionsTitle),
      content: SizedBox(
        width: 440,
        child: sessions.isEmpty
            ? Text(l10n.noCompletedSessions)
            : ListView.separated(
                shrinkWrap: true,
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, index) {
                  final review = sessions[index];
                  final accuracy = (review.accuracy * 100).toStringAsFixed(1);
                  return Semantics(
                    label: l10n.sessionHistorySemantics(
                      review.metadata.contestName,
                      accuracy,
                    ),
                    child: ListTile(
                      onTap: () {
                        final messenger = ScaffoldMessenger.of(context);
                        final settings = context.read<AppSettings>();
                        settings
                          ..pendingQuestionSeed = review.metadata.questionSeed
                          ..pendingAudioSeed = review.metadata.audioSeed
                          ..pendingReplayRunId = review.metadata.runId
                          ..contestId = review.metadata.contestId
                          ..contestModeId = review.metadata.modeId
                          ..difficulty = TrainingDifficulty.fromId(
                            review.metadata.difficultyId,
                          );
                        Navigator.pop(context);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.replaySeedSnack(
                                review.metadata.questionSeed,
                              ),
                            ),
                          ),
                        );
                      },
                      title: Text(
                        '${review.metadata.contestName} · '
                        '${l10n.trainingModeLabelById(review.metadata.modeId)}',
                      ),
                      subtitle: Text(
                        l10n.sessionHistorySubtitle(
                          review.qsoCount,
                          accuracy,
                          review.qsosPerHour.toStringAsFixed(1),
                          review.metadata.questionSeed,
                        ),
                      ),
                      trailing: Text(l10n.sessionHistoryScore(review.score)),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
