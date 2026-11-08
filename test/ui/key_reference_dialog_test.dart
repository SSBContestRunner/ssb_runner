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

  testWidgets('lists every function key and all six fixed shortcuts', (
    tester,
  ) async {
    final settings = await _createSettings();
    await _openReference(tester, settings);

    expect(find.text('Keyboard reference'), findsOneWidget);
    expect(find.text('Function keys'), findsOneWidget);
    expect(find.text('Fixed shortcuts'), findsOneWidget);

    for (var index = 1; index <= 11; index++) {
      expect(find.text('F$index'), findsOneWidget);
    }
    // F12 is listed once as a function key; it no longer appears as a static
    // "clear the input" shortcut because the binding is configurable.
    expect(find.text('F12'), findsOneWidget);
    expect(find.text('Unassigned'), findsNWidgets(3));
    expect(find.text('CQ'), findsOneWidget);
    expect(find.text('Wipe'), findsOneWidget);

    expect(find.text('Tab'), findsNWidgets(2));
    expect(find.text('Shift'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text(';'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);

    expect(find.text('clear the input fields'), findsNothing);
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

  testWidgets('conflicts are listed inline and saving keeps the dialog open', (
    tester,
  ) async {
    final prefs = await _createPrefs();
    final settings = _ConflictingSettings(prefs: prefs);
    await _openReference(tester, settings);

    await tester.tap(find.text('Customize function keys'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('CQ is assigned to both F1 and F2.'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(KeyBindingsDialog), findsOneWidget);
    expect(prefs.getString('setting_function_key_F1'), isNull);
    expect(prefs.getString('setting_function_key_F2'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an action owned by another key is disabled in the editor', (
    tester,
  ) async {
    final prefs = await _createPrefs();
    final settings = _ConflictingSettings(prefs: prefs);
    await _openReference(tester, settings);

    await tester.tap(find.text('Customize function keys'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final buttons = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .toList();
    expect(buttons, hasLength(12));

    final f2Items = buttons[1].items!;
    final cq = f2Items.firstWhere((item) => item.value == 'cq');
    final spare = f2Items.firstWhere((item) => item.value == 'spare');
    final tu = f2Items.firstWhere((item) => item.value == 'tu');
    expect(cq.enabled, isFalse);
    expect(spare.enabled, isTrue);
    expect(tu.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}

/// Forces the editor to open with a conflicting draft, which the normal loader
/// would already have repaired.
class _ConflictingSettings extends AppSettings {
  _ConflictingSettings({required super.prefs});

  @override
  List<FunctionKeyBinding> get functionKeyBindings => [
    for (final key in FunctionKey.values)
      FunctionKeyBinding(
        key,
        switch (key) {
          FunctionKey.f1 || FunctionKey.f2 => OperationAction.cq,
          _ => null,
        },
      ),
  ];
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

Future<SharedPreferencesWithCache> _createPrefs() async {
  return SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
}

Future<AppSettings> _createSettings() async {
  final prefs = await _createPrefs();
  return AppSettings(prefs: prefs);
}
