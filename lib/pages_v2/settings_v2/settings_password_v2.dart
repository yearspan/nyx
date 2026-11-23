import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

/// V2 登录密码修改页
///
/// 入口：个人设置 → 隐私与安全 → 登录密码。
/// 顶部导航栏右侧打勾按钮提交，无底部按钮。
class SettingsPasswordV2 extends StatefulWidget {
  const SettingsPasswordV2({super.key});

  @override
  State<SettingsPasswordV2> createState() => _SettingsPasswordV2State();
}

class _SettingsPasswordV2State extends State<SettingsPasswordV2> {
  final TextEditingController oldPasswordController = TextEditingController();
  final TextEditingController newPassword1Controller = TextEditingController();
  final TextEditingController newPassword2Controller = TextEditingController();

  String? oldPasswordError;
  String? newPassword1Error;
  String? newPassword2Error;

  bool loading = false;

  bool oldPasswordVisible = false;
  bool newPassword1Visible = false;
  bool newPassword2Visible = false;

  @override
  void initState() {
    super.initState();
    // 输入内容变化时刷新打勾按钮的可用状态
    oldPasswordController.addListener(_onTextChanged);
    newPassword1Controller.addListener(_onTextChanged);
    newPassword2Controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  bool get _allFilled =>
      oldPasswordController.text.isNotEmpty &&
      newPassword1Controller.text.isNotEmpty &&
      newPassword2Controller.text.isNotEmpty;

  Future<void> changePassword() async {
    final l10n = L10n.of(context);
    setState(() {
      oldPasswordError = newPassword1Error = newPassword2Error = null;
    });
    if (oldPasswordController.text.isEmpty) {
      setState(() {
        oldPasswordError = l10n.pleaseEnterYourPassword;
      });
      return;
    }
    if (newPassword1Controller.text.isEmpty ||
        newPassword1Controller.text.length < 6) {
      setState(() {
        newPassword1Error = l10n.pleaseChooseAStrongPassword;
      });
      return;
    }
    if (newPassword1Controller.text != newPassword2Controller.text) {
      setState(() {
        newPassword2Error = l10n.passwordsDoNotMatch;
      });
      return;
    }

    setState(() => loading = true);
    final client = Matrix.of(context).client;
    try {
      await client.changePassword(
        newPassword1Controller.text,
        oldPassword: oldPasswordController.text,
      );
      if (!mounted) return;
      V2Toast.show(l10n.passwordHasBeenChanged);
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    oldPasswordController.removeListener(_onTextChanged);
    newPassword1Controller.removeListener(_onTextChanged);
    newPassword2Controller.removeListener(_onTextChanged);
    oldPasswordController.dispose();
    newPassword1Controller.dispose();
    newPassword2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(
            title: l10n.loginPassword,
            action: _buildSubmitButton(context),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _PasswordField(
                  label: l10n.oldPassword,
                  controller: oldPasswordController,
                  visible: oldPasswordVisible,
                  onToggleVisible: () =>
                      setState(() => oldPasswordVisible = !oldPasswordVisible),
                  errorText: oldPasswordError,
                  readOnly: loading,
                  hint: l10n.enterPassword,
                ),
                SizedBox(height: 16),
                _PasswordField(
                  label: l10n.newPassword,
                  controller: newPassword1Controller,
                  visible: newPassword1Visible,
                  onToggleVisible: () => setState(
                    () => newPassword1Visible = !newPassword1Visible,
                  ),
                  errorText: newPassword1Error,
                  readOnly: loading,
                  hint: l10n.enterPassword,
                ),
                SizedBox(height: 16),
                _PasswordField(
                  label: l10n.repeatPassword,
                  controller: newPassword2Controller,
                  visible: newPassword2Visible,
                  onToggleVisible: () => setState(
                    () => newPassword2Visible = !newPassword2Visible,
                  ),
                  errorText: newPassword2Error,
                  readOnly: loading,
                  hint: l10n.enterPassword,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 右上角打勾提交按钮：
  /// - 加载中显示转圈
  /// - 三个输入框均有内容时为黑色可点击，否则置灰不可点击
  Widget _buildSubmitButton(BuildContext context) {
    if (loading) {
      return Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(V2Theme.of(context).accent),
          ),
        ),
      );
    }
    final enabled = _allFilled;
    return V2CircleIconButton(
      icon: Icons.check,
      iconColor: enabled ? Theme.of(context).colorScheme.onSurface : V2Theme.of(context).textSecondary,
      onTap: enabled ? changePassword : () {},
    );
  }
}

/// 带标签 + 错误提示的密码输入框
class _PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggleVisible;
  final String? errorText;
  final bool readOnly;
  final String hint;

  const _PasswordField({
    required this.label,
    required this.controller,
    required this.visible,
    required this.onToggleVisible,
    required this.readOnly,
    required this.hint,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FieldLabel(label),
        SizedBox(height: 6),
        V2TextInput(
          controller: controller,
          hint: hint,
          obscure: !visible,
          readOnly: readOnly,
          trailing: V2VisibilityToggle(
            visible: visible,
            onTap: onToggleVisible,
          ),
        ),
        if (errorText != null) ...[
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.only(left: 16),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
            ),
          ),
        ],
      ],
    );
  }
}
