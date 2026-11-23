import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

/// V2 右上角通用「打勾提交」按钮
///
/// 统一用于群资料编辑、发起投票等需要提交的页面：
/// - 默认显示黑色打勾图标，点击触发 [onTap]
/// - [isLoading] 为 true 时替换为主题色加载圈，且禁用点击
/// - [enabled] 为 false 时打勾图标变灰且禁用点击（输入内容为空时使用）
class V2CheckButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isLoading;
  final bool enabled;

  const V2CheckButton({
    super.key,
    required this.onTap,
    this.isLoading = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final v2 = V2Theme.of(context);
    final canTap = enabled && !isLoading && onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canTap ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: v2.cardBackground,
          shape: BoxShape.circle,
          border: isDark?
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
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(v2.accent),
                ),
              )
            : Icon(
                Icons.check,
                size: 24,
                color: enabled
                    ? Theme.of(context).colorScheme.onSurface
                    : v2.textSecondary,
              ),
      ),
    );
  }
}
