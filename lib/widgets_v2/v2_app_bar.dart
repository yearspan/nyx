import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

/// V2 统一导航栏
///
/// 布局（参考设计稿）：
/// - 左侧：圆形白底阴影返回按钮（可通过 [circularBack] 改为纯图标，
///   用于扫码页等深色/沉浸式背景）
/// - 中间：居中标题，下方可带一行子标题（如在线状态）
/// - 右侧：自定义 widget（如「完成」胶囊按钮、更多按钮）
///
/// 该组件是普通 Widget（自带状态栏安全区），请放在页面 body 的 Column 顶部，
/// 不要传给 Scaffold.appBar。
class V2AppBar extends StatelessWidget {
  /// 主标题
  final String? title;

  /// 自定义主标题组件（非空时优先于 [title]，用于在标题旁附加图标等）
  final Widget? titleWidget;

  /// 子标题文字（标题下方一行小字）
  final String? subtitle;

  /// 自定义子标题组件（非空时优先于 [subtitle]，用于 PresenceBuilder
  /// 这类需要自行刷新的内容）
  final Widget? subtitleWidget;

  /// 右侧自定义区域
  final Widget? action;

  /// 右侧多个操作（[action] 非空时忽略）
  final List<Widget>? actions;

  /// 返回回调，为空且 [showBack] 为 true 时默认 Navigator.maybePop
  final VoidCallback? onBack;

  /// 是否显示返回按钮
  final bool showBack;

  /// 返回按钮是否为圆形白底阴影样式（false = 纯图标，沉浸式页面用）
  final bool circularBack;

  /// 导航栏背景色，为空时使用当前主题的 scaffoldBackground
  final Color? backgroundColor;

  /// 标题/返回图标前景色，为空时使用当前主题的 onSurface
  final Color? foregroundColor;

  /// 子标题颜色
  final Color? subtitleColor;

  /// 自定义返回图标
  final IconData backIcon;

  const V2AppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.action,
    this.actions,
    this.onBack,
    this.showBack = true,
    this.circularBack = true,
    this.backgroundColor,
    this.foregroundColor,
    this.subtitleColor,
    this.backIcon = Icons.chevron_left,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final bg = backgroundColor ?? v2.scaffoldBackground;
    final fg = foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    final subColor = subtitleColor ?? v2.textSecondary;

    return Container(
      width: double.infinity,
      color: bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 左侧返回
              if (showBack)
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: circularBack
                        ? V2CircleIconButton(
                            icon: backIcon,
                            iconColor: fg,
                            onTap: onBack ??
                                () => Navigator.of(context).maybePop(),
                          )
                        : IconButton(
                            icon: Icon(backIcon, color: fg),
                            onPressed: onBack ??
                                () => Navigator.of(context).maybePop(),
                          ),
                  ),
                ),
              // 中间标题 + 子标题
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 64),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (titleWidget != null)
                          titleWidget!
                        else if (title != null)
                          Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                          ),
                        if (subtitle != null || subtitleWidget != null)
                          Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: subtitleWidget ??
                                Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: subColor,
                                  ),
                                ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // 右侧操作区
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: action != null
                        ? [action!]
                        : (actions ?? const <Widget>[]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 导航栏用的圆形白底阴影图标按钮（返回键 / 更多键同款）
class V2CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Color? background;
  final double size;
  final VoidCallback onTap;
  final Color? borderColor;

  const V2CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.background,
    this.size = 40,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final v2 = V2Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? v2.cardBackground,
          shape: BoxShape.circle,
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 1)
              : isDark?
          Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.3), width: 1)
              :null,
          boxShadow: [
            BoxShadow(
              color: isDark?Colors.white.withValues(alpha: 0.2):Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 24,
          color: iconColor ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
