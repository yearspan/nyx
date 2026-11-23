import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';

/// V2 表单类页面公共组件（绑定邮箱 / 修改邮箱等流程复用）。

/// 顶部图标 + 标题 + 描述
class V2FormHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const V2FormHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: v2.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: Colors.white),
          ),
          SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: v2.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 输入框上方小标签
class V2FieldLabel extends StatelessWidget {
  final String text;
  const V2FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: V2Theme.of(context).textSecondary),
    );
  }
}

/// 白色圆角输入框
class V2TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool readOnly;
  final TextInputType? keyboardType;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool autocorrect;

  const V2TextInput({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.readOnly = false,
    this.keyboardType,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction,
    this.autofillHints,
    this.autocorrect = true,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: v2.cardBackground,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              readOnly: readOnly,
              keyboardType: keyboardType,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              autofocus: autofocus,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
              autocorrect: autocorrect,
              style: TextStyle(fontSize: 16, color: onSurface),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  color: v2.textSecondary,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 密码可见性切换
class V2VisibilityToggle extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;
  const V2VisibilityToggle({
    super.key,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Icon(
        visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 18,
        color: V2Theme.of(context).textSecondary,
      ),
    );
  }
}

/// 主题色圆角大按钮
class V2PrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  const V2PrimaryButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final disabled = busy || onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: disabled ? v2.accent.withValues(alpha: 0.5) : v2.accent,
          borderRadius: BorderRadius.circular(27),
        ),
        child: busy
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

/// 表单校验提示（接口未就绪前用 SnackBar 承担反馈）
void v2ShowFormHint(BuildContext context, String text) {
  V2Toast.show(text);
}

extension V2FormString on String {
  static final RegExp _emailRegex = RegExp(r'(.+)@(.+)\.(.+)');
  static final RegExp _phoneRegex = RegExp(
    r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$',
  );
  bool get isEmail => _emailRegex.hasMatch(this);
  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}
