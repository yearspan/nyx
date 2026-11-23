import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

/// V2 风格单按钮对话框：标题 + 正文 + 一个主按钮。
///
/// 用于只需「确认」一个操作的场景（如热更新就绪提示），
/// 样式与 [V2ConfirmDialog] 保持一致，但没有取消按钮、
/// 点击遮罩不可关闭，必须点击主按钮。
class V2SingleButtonDialog extends StatelessWidget {
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onTap;

  const V2SingleButtonDialog({
    super.key,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onTap,
  });

  /// 弹出对话框，返回点击结果（始终为 true，因为只有一个按钮）。
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => V2SingleButtonDialog(
        title: title,
        message: message,
        buttonLabel: buttonLabel,
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            decoration: BoxDecoration(
              color: v2.cardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                ),
                // 正文
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: v2.textSecondary),
                  ),
                ),
                // 分割线
                Container(height: 1, color: v2.divider),
                // 按钮
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      foregroundColor: v2.accent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                    ),
                    child: Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
