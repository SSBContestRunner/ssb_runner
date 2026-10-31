import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

void main() {
  test('the light scheme uses the Clear Sky palette, not seed derivation', () {
    final scheme = AppTheme.light.colorScheme;

    expect(scheme.brightness, Brightness.light);
    expect(scheme.primary, AppColors.brandBlue);
    expect(scheme.primaryContainer, const Color(0xFFD5E6FF));
    expect(scheme.secondary, const Color(0xFF006B85));
    expect(scheme.tertiary, const Color(0xFF8A5200));
    expect(scheme.error, const Color(0xFFBA1A1A));
    expect(scheme.surface, const Color(0xFFF4F8FE));
    expect(scheme.surfaceContainerLow, const Color(0xFFFBFDFF));
    expect(scheme.surfaceContainer, const Color(0xFFEAF1FA));
    expect(scheme.surfaceContainerHighest, const Color(0xFFD5E2F1));
    expect(scheme.onSurface, const Color(0xFF182030));
    expect(scheme.outlineVariant, const Color(0xFFC3D2E2));

    final semantic = AppTheme.light.extension<AppSemanticColors>()!;
    expect(semantic.success, const Color(0xFF177D4B));
    expect(semantic.successContainer, const Color(0xFFC6F2DC));
  });

  test('the dark scheme uses deep navy surfaces and lifted primary', () {
    final scheme = AppTheme.dark.colorScheme;

    expect(scheme.brightness, Brightness.dark);
    expect(scheme.primary, const Color(0xFFA7CCFF));
    expect(scheme.surface, const Color(0xFF0B1526));
    expect(scheme.surfaceContainerLow, const Color(0xFF111E32));
    expect(scheme.secondary, const Color(0xFF6FD3ED));
    expect(scheme.tertiary, const Color(0xFFFFD08A));

    final semantic = AppTheme.dark.extension<AppSemanticColors>()!;
    expect(semantic.success, const Color(0xFF6FDFAC));
    expect(semantic.successContainer, const Color(0xFF0C4A32));
  });

  testWidgets('data text is Iosevka with tabular figures', (tester) async {
    late TextStyle style;
    late ThemeData theme;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            style = AppDataText.style(context);
            theme = Theme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontFamily, 'Iosevka');
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Iosevka');
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      contains('PingFang SC'),
    );
  });
}
