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

  void _setupAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) {
        return;
      }
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QsoRecordListCubit, List<QsoResult>>(
      builder: (context, qsos) {
        _setupAutoScroll();
        if (qsos.isEmpty) {
          return const SizedBox.expand();
        }
        return Scrollbar(
          controller: _controller,
          child: ListView.builder(
            controller: _controller,
            itemBuilder: (context, index) => QsoRecordRow(
              item: qsos[index],
              isLatest: index == qsos.length - 1,
            ),
            itemCount: qsos.length,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
