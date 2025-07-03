import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_contest_runner/ui/main_settings.dart';
import 'package:ssb_contest_runner/ui/qso_record_table.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<Cubit, void>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            direction: Axis.vertical,
            spacing: 15.0,
            children: [
              Expanded(child: _TopPanel()),
              _BottomPanel(),
            ],
          ),
        );
      },
    );
  }
}

class _TopPanel extends StatelessWidget {
  const _TopPanel();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18.0,
      direction: Axis.vertical,
      children: [
        Expanded(child: QsoRecordTable()),
        MainSettings(),
      ],
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel();

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.green, child: const Text('Bottom Panel'));
  }
}
