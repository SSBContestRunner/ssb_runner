import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/key_reference_dialog.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('lists every function key and all seven global shortcuts', (
    tester,
  ) async {
    final settings = await _createSettings();
    await _openReference(tester, settings);

    expect(find.text('Keyboard reference'), findsOneWidget);
    expect(find.text('Function keys'), findsOneWidget);
    expect(find.text('Shortcuts'), findsOneWidget);

    for (var index = 1; index <= 11; index++) {
      expect(find.text('F$index'), findsOneWidget);
    }
    // F12 appears both as a function key and in the Esc shortcut hint.
    expect(find.text('F12'), findsNWidgets(2));
    expect(find.text('Unassigned'), findsNWidgets(3));
    expect(find.text('CQ'), findsOneWidget);
    expect(find.text('Wipe'), findsOneWidget);

    expect(find.text('Tab'), findsNWidgets(2));
    expect(find.text('Shift'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text(';'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('F12'), findsWidgets);
    expect(find.text('Esc'), findsOneWidget);

    expect(find.text('clear the input fields'), findsOneWidget);
    expect(
      find.text('stop sending (does not abandon the round)'),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('customize opens the twelve-key editor and saves', (
    tester,
  ) async {
    final settings = await _createSettings();
    await _openReference(tester, settings);

    await tester.tap(find.text('Customize function keys'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(12));

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(settings.functionKeyBindings, hasLength(12));
    expect(
      settings.functionKeyBindings[FunctionKey.f1.index].action,
      OperationAction.cq,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('running sessions hide customization and explain the lock', (
    tester,
  ) async {
    final settings = await _createSettings();
    await _openReference(tester, settings, canCustomize: false);

    expect(find.text('Customize function keys'), findsNothing);
    expect(
      find.text("Function keys can't be changed while a session runs."),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });
}

Future<void> _openReference(
  WidgetTester tester,
  AppSettings settings, {
  bool canCustomize = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showKeyReferenceDialog(
                context,
                settings: settings,
                canCustomize: canCustomize,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<AppSettings> _createSettings() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  return AppSettings(prefs: prefs);
}
