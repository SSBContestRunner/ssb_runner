import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

Future<void> showKeyReferenceDialog(
  BuildContext context, {
  required AppSettings settings,
  required bool canCustomize,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        KeyReferenceDialog(settings: settings, canCustomize: canCustomize),
  );
}

class KeyReferenceDialog extends StatelessWidget {
  const KeyReferenceDialog({
    super.key,
    required this.settings,
    required this.canCustomize,
  });

  final AppSettings settings;
  final bool canCustomize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Semantics(
        label: l10n.keyTipsSemantics,
        child: AlertDialog(
          scrollable: true,
          title: Text(l10n.keyReferenceTitle),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.keyReferenceFunctions,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: settings.functionKeysRevision,
                    builder: (context, _, _) => Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final binding in functionKeysFromSettings(
                          settings,
                        ))
                          SizedBox(
                            width: 172,
                            child: _FunctionKeyItem(
                              keyLabel: binding.key.label,
                              actionLabel:
                                  binding.action?.label ??
                                  l10n.keyReferenceSpare,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.keyReferenceShortcuts,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  _ShortcutRow(
                    description: l10n.keyTipNextInput,
                    keys: const ['Tab'],
                  ),
                  _ShortcutRow(
                    description: l10n.keyTipPreviousInput,
                    keys: const ['Shift', 'Tab'],
                  ),
                  _ShortcutRow(
                    description: l10n.keyTipToggleCallExchange,
                    keys: const ['Space'],
                  ),
                  _ShortcutRow(
                    description: l10n.keyTipSendCallExchange,
                    keys: const [';'],
                  ),
                  _ShortcutRow(
                    description: l10n.keyTipSubmit,
                    keys: const ['Enter'],
                  ),
                  _ShortcutRow(
                    description: l10n.keyTipClearInput,
                    keys: const ['F12'],
                  ),
                  _ShortcutRow(
                    description: l10n.keyTipStopSending,
                    keys: const ['Esc'],
                  ),
                  if (!canCustomize) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.functionKeysRunningLock,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (canCustomize)
              TextButton.icon(
                onPressed: () => _openCustomize(context),
                icon: const Icon(Icons.keyboard_outlined, size: 18),
                label: Text(l10n.customizeFunctionKeys),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCustomize(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => KeyBindingsDialog(settings: settings),
    );
  }
}

class _FunctionKeyItem extends StatelessWidget {
  const _FunctionKeyItem({required this.keyLabel, required this.actionLabel});

  final String keyLabel;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSpare =
        actionLabel == AppLocalizations.of(context).keyReferenceSpare;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Kbd(label: keyLabel, minWidth: 28),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              actionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isSpare
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.55)
                    : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.description, required this.keys});

  final String description;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: 12),
          for (final key in keys) ...[
            _Kbd(label: key),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd({required this.label, this.minWidth = 20});

  final String label;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      height: 22,
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
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Edits the F1–F12 bindings. Kept from the previous settings panel; saving
/// writes through [AppSettings] so the console and reference refresh together.
class KeyBindingsDialog extends StatefulWidget {
  const KeyBindingsDialog({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<KeyBindingsDialog> createState() => _KeyBindingsDialogState();
}

class _KeyBindingsDialogState extends State<KeyBindingsDialog> {
  late final Map<FunctionKey, String> bindings;

  @override
  void initState() {
    super.initState();
    bindings = {
      for (final binding in widget.settings.functionKeyBindings)
        binding.key: binding.action?.id ?? _spareBindingValue,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.functionKeysTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          children: [
            for (final key in FunctionKey.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  initialValue: bindings[key],
                  decoration: InputDecoration(labelText: key.label),
                  items: [
                    DropdownMenuItem(
                      value: _spareBindingValue,
                      child: Text(l10n.keyReferenceSpare),
                    ),
                    for (final action in OperationAction.values)
                      DropdownMenuItem(
                        value: action.id,
                        child: Text(action.label),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) setState(() => bindings[key] = id);
                  },
                ),
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
          onPressed: () async {
            final assigned = bindings.values
                .where((id) => id != _spareBindingValue)
                .toList();
            if (assigned.toSet().length != assigned.length) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.functionKeysUnique)));
              return;
            }
            await widget.settings.setFunctionKeyBindings([
              for (final key in FunctionKey.values)
                FunctionKeyBinding(key, OperationAction.fromId(bindings[key])),
            ]);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

const _spareBindingValue = 'spare';
