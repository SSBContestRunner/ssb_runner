import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_contest_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_contest_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';

class QsoRecordList extends StatelessWidget {
  const QsoRecordList({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final surfaceContainerHighest = colorScheme.surfaceContainerHighest;

    final bodySmall = TextTheme.of(context).bodySmall;

    return BlocProvider(
      create: (context) => QsoRecordListCubit(
        appDatabase: context.read(),
        contestManager: context.read(),
      ),
      child: BlocBuilder<QsoRecordListCubit, List<QsoResult>>(
        builder: (context, qsos) {
          return ListView.separated(
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
                            children: [Text('00:00:00', style: bodySmall)],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              _textOfQso(colorScheme, bodySmall, item.call),
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
                                  bodySmall,
                                  true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              _textOfQso(colorScheme, bodySmall, item.exchange),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Text(item.corrections, style: bodySmall),
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
}
