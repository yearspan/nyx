import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// V2 风格确认对话框
/// 标题 + 正文 + 取消 / 确认 按钮
/// 主按钮 teal 填充，次按钮白底描边
///
/// 若传入 [future]，点击确认后按钮文字会切换为加载转圈，
/// 执行期间不可操作，完成后自动关闭对话框（成功返回 true）。
class V2ConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String? confirmLabel;
  final String? cancelLabel;
  final Future<void> Function()? future;

  const V2ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel,
    this.cancelLabel,
    this.future,
  });

  /// 弹出对话框，返回 true=确认，false=取消，null=外部关闭
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    Future<void> Function()? future,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => V2ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        future: future,
      ),
    );
  }

  @override
  State<V2ConfirmDialog> createState() => _V2ConfirmDialogState();
}

class _V2ConfirmDialogState extends State<V2ConfirmDialog> {
  bool _loading = false;

  Future<void> _onConfirm() async {
    if (_loading) return;
    if (widget.future == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.future!();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        // 失败时不关闭，恢复可操作状态
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final v2 = V2Theme.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return PopScope(
      canPop: !_loading,
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
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    widget.title,
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
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: v2.textSecondary),
                  ),
                ),
                // 分割线
                Container(height: 1, color: v2.divider),
                // 按钮区
                Row(
                  children: [
                    // 取消（白底描边）
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            foregroundColor: _loading
                                ? v2.textSecondary
                                : onSurface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                              ),
                            ),
                          ),
                          child: Text(
                            widget.cancelLabel ?? l10n.cancel,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, height: 48, color: v2.divider),
                    // 确认（teal 填充）
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: TextButton(
                          onPressed: _loading ? null : _onConfirm,
                          style: TextButton.styleFrom(
                            foregroundColor: _loading
                                ? v2.textSecondary
                                : v2.accent,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                          ),
                          child: _loading
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      v2.accent,
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.confirmLabel ?? l10n.ok,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
