import 'package:material_ui/material_ui.dart';

/// V2 UI 专属主题数据，作为 [ThemeExtension] 注册到明暗主题中。
///
/// 浅色参考设计稿，深色参考微信深色模式配色。
@immutable
class V2ThemeData extends ThemeExtension<V2ThemeData> {
  final Color accent;
  final Color accentLight;
  final Color scaffoldBackground;
  final Color cardBackground;
  final Color textSecondary;
  final Color divider;

  const V2ThemeData({
    required this.accent,
    required this.accentLight,
    required this.scaffoldBackground,
    required this.cardBackground,
    required this.textSecondary,
    required this.divider,
  });

  /// 浅色主题（珊瑚橙主色风格）
  static const V2ThemeData light = V2ThemeData(
    accent: Color(0xFFFF6B4A),
    accentLight: Color(0xFFFFE9E2),
    scaffoldBackground: Color(0xFFF5F6F7),
    cardBackground: Colors.white,
    textSecondary: Color(0xFF8A8F98),
    divider: Color(0xFFECECEC),
  );

  /// 深色主题（微信风格）
  static const V2ThemeData dark = V2ThemeData(
    accent: Color(0xFFFF6B4A),
    accentLight: Color(0xFF3A1A18),
    scaffoldBackground: Color(0xFF000000),
    cardBackground: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF8E8E93),
    divider: Color(0xFF2C2C2E),
  );

  @override
  V2ThemeData copyWith({
    Color? accent,
    Color? accentLight,
    Color? scaffoldBackground,
    Color? cardBackground,
    Color? textSecondary,
    Color? divider,
  }) {
    return V2ThemeData(
      accent: accent ?? this.accent,
      accentLight: accentLight ?? this.accentLight,
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
    );
  }

  @override
  V2ThemeData lerp(ThemeExtension<V2ThemeData>? other, double t) {
    if (other is! V2ThemeData) return this;
    return V2ThemeData(
      accent: Color.lerp(accent, other.accent, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      scaffoldBackground:
          Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

/// V2 主题访问入口。
///
/// 通过 [V2Theme.of] 获取当前主题下的 [V2ThemeData]，颜色会随明暗主题自动切换。
/// 静态常量 [light] 仅作为无 context 场景下的兜底默认值。
abstract class V2Theme {
  static const V2ThemeData light = V2ThemeData.light;

  /// 主圆角
  static const double radius = 25.0;

  /// 大圆角（卡片）
  static const double cardRadius = 16.0;

  /// 获取当前主题下的 V2 主题数据
  static V2ThemeData of(BuildContext context) {
    final ext = Theme.of(context).extension<V2ThemeData>();
    return ext ?? V2ThemeData.light;
  }

  // ---- 以下为兼容旧调用的静态兜底色（建议改用 of(context).xxx）----
  static Color get accent => light.accent;
  static Color get accentLight => light.accentLight;
  static Color get scaffoldBackground => light.scaffoldBackground;
  static Color get cardBackground => light.cardBackground;
  static Color get textSecondary => light.textSecondary;
  static Color get divider => light.divider;
}
