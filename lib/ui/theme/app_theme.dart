import 'package:flutter/material.dart';
import 'package:ssb_runner/common/constants.dart';

/// Brand anchor and the "Clear Sky" (晴空) palette from
/// docs/design/ui_rework_a_console_design.md §4.3.1.
abstract final class AppColors {
  static const brandBlue = Color(0xFF0059BA);

  static const lightPrimary = Color(0xFF0059BA);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFD5E6FF);
  static const lightOnPrimaryContainer = Color(0xFF002A56);
  static const lightInversePrimary = Color(0xFFA3C9FF);

  static const lightSecondary = Color(0xFF006B85);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFC6EAF5);
  static const lightOnSecondaryContainer = Color(0xFF003441);

  static const lightTertiary = Color(0xFF8A5200);
  static const lightOnTertiary = Color(0xFFFFFFFF);
  static const lightTertiaryContainer = Color(0xFFFFE3B3);
  static const lightOnTertiaryContainer = Color(0xFF2E1B00);

  static const lightError = Color(0xFFBA1A1A);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFFDAD6);
  static const lightOnErrorContainer = Color(0xFF410002);

  static const lightSuccess = Color(0xFF177D4B);
  static const lightOnSuccess = Color(0xFFFFFFFF);
  static const lightSuccessContainer = Color(0xFFC6F2DC);
  static const lightOnSuccessContainer = Color(0xFF00391F);

  static const lightSurface = Color(0xFFF4F8FE);
  static const lightOnSurface = Color(0xFF182030);
  static const lightSurfaceVariant = Color(0xFFD6E2F0);
  static const lightOnSurfaceVariant = Color(0xFF4D5E73);
  static const lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const lightSurfaceContainerLow = Color(0xFFFBFDFF);
  static const lightSurfaceContainer = Color(0xFFEAF1FA);
  static const lightSurfaceContainerHigh = Color(0xFFE1EAF6);
  static const lightSurfaceContainerHighest = Color(0xFFD5E2F1);
  static const lightInverseSurface = Color(0xFF2C3547);
  static const lightOnInverseSurface = Color(0xFFEEF2FA);
  static const lightOutline = Color(0xFF6C7E93);
  static const lightOutlineVariant = Color(0xFFC3D2E2);
  static const lightShadow = Color(0xFF0D2A52);
  static const lightScrim = Color(0x52040C1A);

  static const darkPrimary = Color(0xFFA7CCFF);
  static const darkOnPrimary = Color(0xFF00315E);
  static const darkPrimaryContainer = Color(0xFF00498C);
  static const darkOnPrimaryContainer = Color(0xFFD6E7FF);
  static const darkInversePrimary = Color(0xFF0059BA);

  static const darkSecondary = Color(0xFF6FD3ED);
  static const darkOnSecondary = Color(0xFF00363F);
  static const darkSecondaryContainer = Color(0xFF00515F);
  static const darkOnSecondaryContainer = Color(0xFFBFEDF7);

  static const darkTertiary = Color(0xFFFFD08A);
  static const darkOnTertiary = Color(0xFF482A00);
  static const darkTertiaryContainer = Color(0xFF653F00);
  static const darkOnTertiaryContainer = Color(0xFFFFE3B3);

  static const darkError = Color(0xFFFFB4AB);
  static const darkOnError = Color(0xFF690005);
  static const darkErrorContainer = Color(0xFF93000A);
  static const darkOnErrorContainer = Color(0xFFFFDAD6);

  static const darkSuccess = Color(0xFF6FDFAC);
  static const darkOnSuccess = Color(0xFF003824);
  static const darkSuccessContainer = Color(0xFF0C4A32);
  static const darkOnSuccessContainer = Color(0xFFB0F5D0);

  static const darkSurface = Color(0xFF0B1526);
  static const darkOnSurface = Color(0xFFE4ECF9);
  static const darkSurfaceVariant = Color(0xFF3C516E);
  static const darkOnSurfaceVariant = Color(0xFFB6C7DD);
  static const darkSurfaceContainerLowest = Color(0xFF070F1C);
  static const darkSurfaceContainerLow = Color(0xFF111E32);
  static const darkSurfaceContainer = Color(0xFF16253C);
  static const darkSurfaceContainerHigh = Color(0xFF1E304A);
  static const darkSurfaceContainerHighest = Color(0xFF273B58);
  static const darkInverseSurface = Color(0xFFE4ECF9);
  static const darkOnInverseSurface = Color(0xFF24324A);
  static const darkOutline = Color(0xFF8497AE);
  static const darkOutlineVariant = Color(0xFF394C66);
  static const darkShadow = Color(0xFF000000);
  static const darkScrim = Color(0x99000000);
}

/// Custom success role. MD3 has no success slot, so it is carried separately
/// and only used for the running status.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}

/// Iosevka is the primary Latin/digit face; CJK and missing glyphs fall back
/// to the platform's sans-serif stack.
const appFontFallback = <String>[
  'Hiragino Sans',
  'PingFang SC',
  'Noto Sans CJK JP',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'Microsoft YaHei',
  'WenQuanYi Micro Hei',
  'sans-serif',
];

/// Data text (callsigns, UTC, scores, timers) uses Iosevka with tabular
/// figures so columns line up.
abstract final class AppDataText {
  static TextStyle style(
    BuildContext context, {
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0.3,
    double? height,
  }) {
    return TextStyle(
      fontFamily: qsoFontFamily,
      fontFamilyFallback: appFontFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

abstract final class AppTheme {
  static ColorScheme get lightScheme => const ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.lightPrimary,
    onPrimary: AppColors.lightOnPrimary,
    primaryContainer: AppColors.lightPrimaryContainer,
    onPrimaryContainer: AppColors.lightOnPrimaryContainer,
    inversePrimary: AppColors.lightInversePrimary,
    secondary: AppColors.lightSecondary,
    onSecondary: AppColors.lightOnSecondary,
    secondaryContainer: AppColors.lightSecondaryContainer,
    onSecondaryContainer: AppColors.lightOnSecondaryContainer,
    tertiary: AppColors.lightTertiary,
    onTertiary: AppColors.lightOnTertiary,
    tertiaryContainer: AppColors.lightTertiaryContainer,
    onTertiaryContainer: AppColors.lightOnTertiaryContainer,
    error: AppColors.lightError,
    onError: AppColors.lightOnError,
    errorContainer: AppColors.lightErrorContainer,
    onErrorContainer: AppColors.lightOnErrorContainer,
    surface: AppColors.lightSurface,
    onSurface: AppColors.lightOnSurface,
    onSurfaceVariant: AppColors.lightOnSurfaceVariant,
    surfaceContainerLowest: AppColors.lightSurfaceContainerLowest,
    surfaceContainerLow: AppColors.lightSurfaceContainerLow,
    surfaceContainer: AppColors.lightSurfaceContainer,
    surfaceContainerHigh: AppColors.lightSurfaceContainerHigh,
    surfaceContainerHighest: AppColors.lightSurfaceContainerHighest,
    inverseSurface: AppColors.lightInverseSurface,
    onInverseSurface: AppColors.lightOnInverseSurface,
    outline: AppColors.lightOutline,
    outlineVariant: AppColors.lightOutlineVariant,
    shadow: AppColors.lightShadow,
    scrim: AppColors.lightScrim,
    surfaceTint: AppColors.lightPrimary,
  );

  static ColorScheme get darkScheme => const ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkOnPrimary,
    primaryContainer: AppColors.darkPrimaryContainer,
    onPrimaryContainer: AppColors.darkOnPrimaryContainer,
    inversePrimary: AppColors.darkInversePrimary,
    secondary: AppColors.darkSecondary,
    onSecondary: AppColors.darkOnSecondary,
    secondaryContainer: AppColors.darkSecondaryContainer,
    onSecondaryContainer: AppColors.darkOnSecondaryContainer,
    tertiary: AppColors.darkTertiary,
    onTertiary: AppColors.darkOnTertiary,
    tertiaryContainer: AppColors.darkTertiaryContainer,
    onTertiaryContainer: AppColors.darkOnTertiaryContainer,
    error: AppColors.darkError,
    onError: AppColors.darkOnError,
    errorContainer: AppColors.darkErrorContainer,
    onErrorContainer: AppColors.darkOnErrorContainer,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkOnSurface,
    onSurfaceVariant: AppColors.darkOnSurfaceVariant,
    surfaceContainerLowest: AppColors.darkSurfaceContainerLowest,
    surfaceContainerLow: AppColors.darkSurfaceContainerLow,
    surfaceContainer: AppColors.darkSurfaceContainer,
    surfaceContainerHigh: AppColors.darkSurfaceContainerHigh,
    surfaceContainerHighest: AppColors.darkSurfaceContainerHighest,
    inverseSurface: AppColors.darkInverseSurface,
    onInverseSurface: AppColors.darkOnInverseSurface,
    outline: AppColors.darkOutline,
    outlineVariant: AppColors.darkOutlineVariant,
    shadow: AppColors.darkShadow,
    scrim: AppColors.darkScrim,
    surfaceTint: AppColors.darkPrimary,
  );

  static ThemeData get light => _build(
    lightScheme,
    const AppSemanticColors(
      success: AppColors.lightSuccess,
      onSuccess: AppColors.lightOnSuccess,
      successContainer: AppColors.lightSuccessContainer,
      onSuccessContainer: AppColors.lightOnSuccessContainer,
    ),
  );

  static ThemeData get dark => _build(
    darkScheme,
    const AppSemanticColors(
      success: AppColors.darkSuccess,
      onSuccess: AppColors.darkOnSuccess,
      successContainer: AppColors.darkSuccessContainer,
      onSuccessContainer: AppColors.darkOnSuccessContainer,
    ),
  );

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      fontFamily: qsoFontFamily,
    );

    final textTheme = base.textTheme
        .apply(
          fontFamily: qsoFontFamily,
          fontFamilyFallback: appFontFallback,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 20,
            height: 26 / 20,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: scheme.onSurface,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 13,
            height: 18 / 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 13,
            height: 19 / 13,
            color: scheme.onSurface,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 11,
            height: 16 / 11,
            letterSpacing: 0.2,
            color: scheme.onSurfaceVariant,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 13,
            height: 18 / 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: scheme.onSurfaceVariant,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontFamily: qsoFontFamily,
            fontFamilyFallback: appFontFallback,
            fontSize: 11,
            height: 16 / 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: scheme.onSurfaceVariant,
          ),
        );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outline),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: qsoFontFamily,
        fontFamilyFallback: appFontFallback,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        width: 480,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primaryContainer,
        selectionHandleColor: scheme.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          minimumSize: const Size(48, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          minimumSize: const Size(64, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(40, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          shape: const CircleBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerLowest,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        suffixStyle: textTheme.bodySmall,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
          labelStyle: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            scheme.surfaceContainerLowest,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.secondaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 6,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 3),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: scheme.outlineVariant,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w400,
        ),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.08),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outline,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      focusColor: scheme.primary.withValues(alpha: 0.12),
      splashColor: scheme.primary.withValues(alpha: 0.08),
      highlightColor: scheme.primary.withValues(alpha: 0.08),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [semantic],
    );
  }
}
