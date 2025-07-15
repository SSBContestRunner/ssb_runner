import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_contest_runner/contest_run/key_event_manager.dart';
import 'package:ssb_contest_runner/settings/setting_constants.dart';
import 'package:ssb_contest_runner/ui/main_cubit.dart';
import 'package:ssb_contest_runner/ui/main_settings.dart';
import 'package:ssb_contest_runner/ui/qso_record_table.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MainCubit(),
      child: BlocBuilder<MainCubit, bool>(
        builder: (context, isShowKeyTips) {
          return Padding(
            padding: const EdgeInsets.only(
              top: 16.0,
              bottom: 12.0,
              left: 16.0,
              right: 16.0,
            ),
            child: Flex(
              direction: Axis.vertical,
              spacing: 16.0,
              children: [
                Expanded(child: _TopPanel()),
                _BottomPanel(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TopPanel extends StatelessWidget {
  const _TopPanel();

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => context.read<AppSettings>(),
      child: Flex(
        spacing: 18.0,
        direction: Axis.horizontal,
        children: [
          Expanded(child: QsoRecordTable()),
          MainSettings(),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MainCubit, bool>(
      builder: (context, _) {
        final theme = Theme.of(context);
        final surfaceVariant = theme.colorScheme.surfaceContainerHighest;

        return SizedBox(
          height: 190,
          child: Flex(
            direction: Axis.horizontal,
            spacing: 18.0,
            children: [
              Expanded(
                flex: 1,
                child: Flex(
                  direction: Axis.vertical,
                  spacing: 18.0,
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
                ),
              ),

              SizedBox(
                width: 240,
                child: Flex(
                  direction: Axis.vertical,
                  spacing: 24,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 92.0,
                      decoration: BoxDecoration(
                        color: surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 6,
                            left: 16,
                            child: Text(
                              'QSO Records',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),

                          Positioned(
                            top: 46,
                            left: 60,
                            right: 60,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '---qsos/h',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 74,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadiusGeometry.circular(
                                    16.0,
                                  ),
                                ),
                              ),
                              onPressed: () {
                                // TODO: Start Run
                              },
                              child: Text(
                                'RUN',
                                style: theme.primaryTextTheme.headlineSmall,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 370,
                child: Flex(
                  direction: Axis.vertical,
                  spacing: 20,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // TODO: add time
                        Text(
                          'time',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onInverseSurface,
                          ),
                        ),
                      ],
                    ),

                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Stack(
                        // TODO: 绘制表格
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QsoInputArea extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorSchema = Theme.of(context).colorScheme;
    final bgColor = colorSchema.primaryContainer;
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
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
              ),
            ),
          ],
        ),
      ),
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
