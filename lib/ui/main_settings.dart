import 'package:flutter/material.dart';
import 'package:ssb_contest_runner/ui/setting_item.dart';

class MainSettings extends StatelessWidget {
  const MainSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 370,
      child: Flex(
        direction: Axis.vertical,
        spacing: 12.0,
        children: [
          SettingItem(title: 'Contest', content: _ContestSettings()),
          SettingItem(title: 'Station', content: _StationSettings()),
          SettingItem(title: 'Options', content: _OptionsSetting()),
        ],
      ),
    );
  }
}

class _ContestSettings extends StatelessWidget {
  const _ContestSettings();

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: Axis.horizontal,
      spacing: 12.0,
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Name',
              suffixIcon: Icon(Icons.arrow_drop_down),
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
    );
  }
}

class _StationSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Callsign',
          ),
        ),
      ],
    );
  }
}

class _OptionsSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: Axis.vertical,
      spacing: 8,
      children: [
        TextField(
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Mode',
          ),
        ),
        TextField(
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Duration',
          ),
        ),
      ],
    );
  }
}
