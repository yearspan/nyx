import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

abstract class FluffyThemes {
  static const double columnWidth = 380.0;

  static const double maxTimelineWidth = columnWidth * 2;

  static const double navRailWidth = 80.0;

  static bool isColumnModeByWidth(double width) =>
      width > columnWidth * 2 + navRailWidth;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      MediaQuery.sizeOf(context).width > FluffyThemes.columnWidth * 3.5;

  static LinearGradient backgroundGradient(BuildContext context, int alpha) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  static const Duration animationDuration = Duration(milliseconds: 250);
  static const Curve animationCurve = Curves.easeInOut;

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    final colorScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: seed ?? Color(AppSettings.colorSchemeSeedInt.value),//const Color(0xFF1E88E5),
      dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
    ).copyWith(
      onSurface: brightness == Brightness.dark
          ? const Color(0xFFE6E1E5)
          : const Color(0xFF1D1B20),
    );
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final dividerColor = brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainer;
    return ThemeData(
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      dividerColor: dividerColor,
      extensions: [
        brightness == Brightness.dark ? V2ThemeData.dark : V2ThemeData.light,
      ],

      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        // 显式指定光标为品牌主色：colorScheme.primary 由 fromSeed 生成，
        // 与品牌主色（V2ThemeData.accent）并非同一颜色，默认 fallback 会导致
        // 光标显示为 fromSeed 产物而非主色调。
        cursorColor: brightness == Brightness.dark
            ? V2ThemeData.dark.accent
            : V2ThemeData.light.accent,
        selectionColor: colorScheme.onSurface.withAlpha(128),
        selectionHandleColor: colorScheme.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: isColumnMode ? 72 : 56,
        surfaceTintColor: isColumnMode ? colorScheme.surface : null,
        backgroundColor: isColumnMode ? colorScheme.surface : null,
        actionsPadding: isColumnMode
            ? const EdgeInsets.symmetric(horizontal: 16.0)
            : null,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness.reversed,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness: brightness.reversed,
          systemNavigationBarColor: colorScheme.surface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(width: 1, color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: isColumnMode
          ? const SnackBarThemeData(
              showCloseIcon: true,
              behavior: SnackBarBehavior.floating,
              width: FluffyThemes.columnWidth * 1.5,
            )
          : const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          elevation: 0,
          padding: const EdgeInsets.all(16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

extension BubbleColorTheme on ThemeData {
  Color get bubbleColor => brightness == Brightness.light
      ? colorScheme.primary
      : colorScheme.primaryContainer;

  Color get onBubbleColor => brightness == Brightness.light
      ? colorScheme.onPrimary
      : colorScheme.onPrimaryContainer;

  Color get secondaryBubbleColor => HSLColor.fromColor(
    brightness == Brightness.light
        ? colorScheme.tertiary
        : colorScheme.tertiaryContainer,
  ).withSaturation(0.5).toColor();
}
