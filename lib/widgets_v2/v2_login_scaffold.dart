import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

/// V2 登录页骨架：web/桌面端居中固定宽高，移动端全屏铺满。
///
/// 与原版 [LoginScaffold] 行为一致，但不强制内置 [AppBar]，
/// 由各页面自行构建 [Scaffold]（含 [V2AppBar]）后传入 [child]。
///
/// - 移动端（窄屏）：直接返回 [child]，保持全屏体验。
/// - web/桌面端：渐变背景 + 居中卡片（maxWidth: 480, maxHeight: 640），
///   避免输入框/按钮铺满屏幕。
class V2LoginScaffold extends StatelessWidget {
  final Widget child;
  const V2LoginScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobileMode = !FluffyThemes.isColumnModeByWidth(
          constraints.maxWidth,
        );
        if (isMobileMode) return child;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.surfaceContainerLow,
                theme.colorScheme.surfaceContainer,
                theme.colorScheme.surfaceContainerHighest,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Material(
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                clipBehavior: Clip.hardEdge,
                elevation: theme.appBarTheme.scrolledUnderElevation ?? 4,
                shadowColor: theme.appBarTheme.shadowColor,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 480,
                    maxHeight: 640,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
