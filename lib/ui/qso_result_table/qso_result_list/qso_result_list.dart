import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';

class QsoRecordList extends StatefulWidget {
  const QsoRecordList({super.key});

  @override
  State<StatefulWidget> createState() {
    return _QsoResultListState();
  }
}

class _QsoResultListState extends State<QsoRecordList> {
  final _controller = ScrollController();

  _QsoResultListState();

  void _setupAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final surfaceContainerHighest = colorScheme.surfaceContainerHighest;

    final qsoItemTextStyle = TextStyle(
      fontSize: 14,
      fontFamily: qsoFontFamily,
      letterSpacing: 1,
      height: 1.4,
    );

    return BlocProvider(
      create: (context) => QsoRecordListCubit(
        appDatabase: context.read(),
        contestManager: context.read(),
      ),
      child: BlocBuilder<QsoRecordListCubit, List<QsoResult>>(
        builder: (context, qsos) {
          _setupAutoScroll();
          return ListView.separated(
            controller: _controller,
            itemBuilder: (context, index) {
              final item = qsos[index];
              return SizedBox(
                height: 20,
                child: Container(
                  color: index % 2 == 0
                      ? Colors.transparent
                      : surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [Text(item.utc, style: qsoItemTextStyle)],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              _textOfQso(
                                  colorScheme, qsoItemTextStyle, item.call),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                item.rst,
                                style: _obtainBodyTextStyle(
                                  colorScheme,
                                  qsoItemTextStyle,
                                  true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              _textOfQso(
                                  colorScheme, qsoItemTextStyle, item.exchange),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Text(item.corrections, style: qsoItemTextStyle),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (context, index) => SizedBox(height: 4),
            itemCount: qsos.length,
          );
        },
      ),
    );
  }

  Widget _textOfQso(
    ColorScheme colorScheme,
    TextStyle? textStyle,
    QsoResultField qsoField,
  ) {
    return Text(
      qsoField.data,
      style: _obtainBodyTextStyle(colorScheme, textStyle, qsoField.isCorrect),
    );
  }

  TextStyle? _obtainBodyTextStyle(
    ColorScheme colorScheme,
    TextStyle? textStyle,
    bool isCorrect,
  ) {
    final onSurface = colorScheme.onSurface;
    final error = colorScheme.error;

    final color = isCorrect ? onSurface : error;
    return textStyle?.copyWith(color: color);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
