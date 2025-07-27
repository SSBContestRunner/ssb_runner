import 'package:flutter/material.dart';
import 'package:ssb_runner/ui/bottom_panel/qso_operation_area.dart';
import 'package:ssb_runner/ui/bottom_panel/qso_speed_area.dart';
import 'package:ssb_runner/ui/bottom_panel/time_and_score/time_and_score_area.dart';

class BottomPanel extends StatelessWidget {
  const BottomPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Flex(
        direction: Axis.horizontal,
        spacing: 18.0,
        children: [
          Expanded(flex: 1, child: QsoOperationArea()),
          SizedBox(width: 240, child: QsoSpeedArea()),
          SizedBox(width: 370, child: TimeAndScoreArea()),
        ],
      ),
    );
  }
}
