import 'package:flutter/material.dart';

class SettingItem extends StatelessWidget {
  final String title;
  final Widget content;

  const SettingItem({required this.title, required this.content, super.key});

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final titleTextStyle = Theme.of(context).textTheme.titleMedium;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4.0),
          topRight: Radius.circular(4.0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          top: 12.0,
          bottom: 12.0,
          left: 14.0,
          right: 14.0,
        ),
        child: Container(
          width: double.infinity,
          color: bgColor,
          child: Flex(
            direction: Axis.vertical,
            spacing: 6.0,
            children: [
              Text(title, style: titleTextStyle),
              content,
            ],
          ),
        ),
      ),
    );
  }
}
