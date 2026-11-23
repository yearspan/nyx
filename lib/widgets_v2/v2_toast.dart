import 'package:fluffychat/config/v2_theme.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:material_ui/material_ui.dart';

/// V2 版通用 Toast / Loading 工具类
/// 所有提示都从底部弹出，统一项目内调用方式
class V2Toast {
  V2Toast._();

  // ---- 主题色（由 [applyTheme] 在主题变化时刷新）----
  /// Toast 背景：浅色模式黑底，深色模式白底
  static Color _toastBackground = Colors.black;

  /// Toast 文字：浅色模式白字，深色模式黑字
  static Color _toastText = Colors.white;

  /// Loading 背景：跟随卡片色
  static Color _loadingBackground = Colors.white;

  /// Loading 文字/指示器色
  static Color _loadingText = Colors.black;
  static Color _indicatorColor = V2Theme.light.accent;

  /// 由 [fluffy_chat_app._EasyLoadingThemeSync] 在主题变化时调用，
  /// 同步 Toast / Loading 所需的颜色到实例。
  static void applyTheme(BuildContext context) {
    final v2 = V2Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Toast 采用反色：浅底黑字 / 深底白字
    _toastBackground = isDark ? Colors.white : Colors.black;
    _toastText = isDark ? Colors.black : Colors.white;
    // Loading 保持卡片底色
    _loadingBackground = v2.cardBackground;
    _loadingText = Theme.of(context).colorScheme.onSurface;
    _indicatorColor = v2.accent;
  }

  /// 短暂提示（默认 2 秒）
  static void show(String msg) {
    EasyLoading.instance
      ..backgroundColor = _toastBackground
      ..textColor = _toastText;
    EasyLoading.showToast(
      msg,
      toastPosition: EasyLoadingToastPosition.center,
      duration: const Duration(milliseconds: 2000),
    );
  }

  /// 显示加载中（带黑色半透明遮罩）
  static void loading([String? status]) {
    EasyLoading.instance
      ..backgroundColor = _loadingBackground
      ..textColor = _loadingText
      ..indicatorColor = _indicatorColor
      ..progressColor = _indicatorColor;
    EasyLoading.show(
      status: status,
      maskType: EasyLoadingMaskType.black,
    );
  }

  /// 关闭加载中 / Toast（立即关闭，无退出动画，避免导航时残留）
  static void dismiss() {
    EasyLoading.dismiss(animation: false);
  }
}
