import 'package:flutter/material.dart';

class SettingItem extends StatelessWidget {
  final String title;
  final Widget content;

  const SettingItem({required this.title, required this.content, super.key});

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final titleTextStyle = Theme.of(context).textTheme.titleMedium;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4.0),
      ),
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(
          top: 12.0,
          bottom: 12.0,
          left: 14.0,
          right: 14.0,
        ),
        child: Flex(
          direction: Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 20.0,
          children: [
            Text(title, style: titleTextStyle),
            content,
          ],
        ),
      ),
    );
  }
}
