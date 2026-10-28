import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/main_page/main_page_cubit.dart';

class KeyTips extends StatelessWidget {
  const KeyTips({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: l10n.keyTipsSemantics,
      container: true,
      child: Container(
        color: colorScheme.scrim.withAlpha(125),
        child: Center(
          child: SizedBox(
            width: 480,
            height: 320,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: colorScheme.surface,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Flex(
                  direction: Axis.vertical,
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Flex(
                          direction: Axis.horizontal,
                          spacing: 16,
                          children: [
                            // Keys
                            Flex(
                              direction: Axis.vertical,
                              spacing: 16,
                              children: _keys(),
                            ),
                            // Descriptions
                            Flex(
                              direction: Axis.vertical,
                              spacing: 30,
                              children: _descriptions(l10n),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              context.read<MainPageCubit>().hideKeyTips();
                            },
                            child: Text(l10n.close),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _keys() {
    return [
      _KeyboardKey(keyText: 'Tab'),
      Flex(
        direction: Axis.horizontal,
        spacing: 10,
        children: [
          _KeyboardKey(keyText: 'Shift'),
          Text('+', style: TextStyle(fontSize: 14)),
          _KeyboardKey(keyText: 'Tab'),
        ],
      ),
      _KeyboardKey(keyText: 'Space'),
      _KeyboardKey(keyText: ';'),
      _KeyboardKey(keyText: 'Enter'),
    ];
  }

  List<Widget> _descriptions(AppLocalizations l10n) {
    final textStyle = TextStyle(fontSize: 14);
    return [
      Text(l10n.keyTipNextInput, style: textStyle),
      Text(l10n.keyTipPreviousInput, style: textStyle),
      Text(l10n.keyTipToggleCallExchange, style: textStyle),
      Text(l10n.keyTipSendCallExchange, style: textStyle),
      Text(l10n.keyTipSubmit, style: textStyle),
    ];
  }
}

class _KeyboardKey extends StatelessWidget {
  final String keyText;

  const _KeyboardKey({required this.keyText});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final textStyle = TextTheme.of(
      context,
    ).labelLarge?.copyWith(color: colorScheme.onSurface);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4.8),
        child: Text(keyText, style: textStyle),
      ),
    );
  }
}
