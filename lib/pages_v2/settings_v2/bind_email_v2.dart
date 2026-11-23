import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

/// 绑定邮箱当前步骤
enum _BindStep {
  email, // 1. 输入邮箱 → 获取验证码
  code, // 2. 输入验证码 → 下一步
  password, // 3. 创建密码 → 完成
}

/// V2 绑定邮箱页（未绑定邮箱的用户使用）。
///
/// 三步流程：
/// 1. 输入邮箱，获取验证码
/// 2. 输入邮箱收到的验证码
/// 3. 设置登录密码
///
/// 注意：发送验证码 / 校验验证码的后端接口尚未提供，
/// 当前网络请求处均为占位（TODO），UI 与交互已完整。
class BindEmailV2 extends StatefulWidget {
  const BindEmailV2({super.key});

  @override
  State<BindEmailV2> createState() => _BindEmailV2State();
}

class _BindEmailV2State extends State<BindEmailV2> {
  _BindStep _step = _BindStep.email;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// 1. 发送验证码
  Future<void> _sendCode() async {
    final l10n = L10n.of(context);
    final email = _emailController.text.trim();
    if (!email.isEmail) {
      v2ShowFormHint(context, l10n.enterValidEmail);
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 调用后端「发送邮箱验证码」接口，入参 email。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _BindStep.code;
    });
  }

  /// 2. 校验验证码
  Future<void> _verifyCode() async {
    final l10n = L10n.of(context);
    if (_codeController.text.trim().isEmpty) {
      v2ShowFormHint(
        context,
        '${l10n.pleaseFillOut} ${l10n.verificationCode}',
      );
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 调用后端「校验邮箱验证码」接口，入参 email + code。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _BindStep.password;
    });
  }

  /// 3. 创建密码并完成
  Future<void> _createPassword() async {
    final l10n = L10n.of(context);
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    if (password.isEmpty) {
      v2ShowFormHint(context, '${l10n.pleaseFillOut} ${l10n.password}');
      return;
    }
    if (password != confirm) {
      v2ShowFormHint(context, l10n.passwordsDoNotMatch);
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 校验通过后绑定邮箱并设置登录密码，入参 email + code + password。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _busy = false);
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.email,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/v2/rooms');
                }
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: switch (_step) {
                  _BindStep.email => _buildEmailStep(l10n),
                  _BindStep.code => _buildCodeStep(l10n),
                  _BindStep.password => _buildPasswordStep(l10n),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 步骤一：输入邮箱
  Widget _buildEmailStep(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FormHeader(
          icon: Icons.markunread_outlined,
          title: l10n.bindEmail,
          description: l10n.bindEmailDescription,
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.email),
        SizedBox(height: 8),
        V2TextInput(
          controller: _emailController,
          hint: l10n.enterEmail,
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: 32),
        V2PrimaryButton(
          label: l10n.getVerificationCode,
          busy: _busy,
          onTap: _sendCode,
        ),
      ],
    );
  }

  /// 步骤二：输入验证码
  Widget _buildCodeStep(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FormHeader(
          icon: Icons.markunread_outlined,
          title: l10n.bindEmail,
          description: l10n.enterCodeSentTo(_emailController.text.trim()),
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.verificationCode),
        SizedBox(height: 8),
        V2TextInput(
          controller: _codeController,
          hint: l10n.enterVerificationCode,
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: 32),
        V2PrimaryButton(label: l10n.next, busy: _busy, onTap: _verifyCode),
      ],
    );
  }

  /// 步骤三：创建密码
  Widget _buildPasswordStep(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FormHeader(
          icon: Icons.lock_outline,
          title: l10n.createPassword,
          description: l10n.createPasswordDescription,
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.password),
        SizedBox(height: 8),
        V2TextInput(
          controller: _passwordController,
          hint: l10n.enterPassword,
          obscure: _obscurePassword,
          trailing: V2VisibilityToggle(
            visible: !_obscurePassword,
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        SizedBox(height: 20),
        V2FieldLabel(l10n.enterPasswordAgain),
        SizedBox(height: 8),
        V2TextInput(
          controller: _confirmPasswordController,
          hint: l10n.enterPassword,
          obscure: _obscureConfirm,
          trailing: V2VisibilityToggle(
            visible: !_obscureConfirm,
            onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        SizedBox(height: 32),
        V2PrimaryButton(
          label: l10n.done,
          busy: _busy,
          onTap: _createPassword,
        ),
      ],
    );
  }
}
