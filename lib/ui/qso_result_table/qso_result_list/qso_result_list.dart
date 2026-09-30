import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_row.dart';

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
            itemBuilder: (context, index) =>
                QsoRecordRow(item: qsos[index], isAlternate: index.isOdd),
            separatorBuilder: (context, index) => SizedBox(height: 4),
            itemCount: qsos.length,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
