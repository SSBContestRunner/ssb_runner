import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/main_page/key_tips.dart';
import 'package:ssb_runner/ui/main_page/main_page_cubit.dart';

void main() {
  testWidgets('Key tips mention F12 clear input and Esc stop sending', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<MainPageCubit>(
          create: (_) => MainPageCubit(),
          child: const Scaffold(body: KeyTips()),
        ),
      ),
    );

    expect(find.text('F12'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('clear the input fields'), findsOneWidget);
    expect(
      find.text('stop sending (does not abandon the round)'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
