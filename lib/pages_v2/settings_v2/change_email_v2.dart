import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// 修改邮箱当前步骤
enum _ChangeStep {
  oldEmail, // 1. 展示旧邮箱 → 获取验证码
  oldCode, // 2. 输入旧邮箱验证码 → 下一步
  newEmail, // 3. 输入新邮箱 → 获取验证码
  newCode, // 4. 输入新邮箱验证码 → 完成
}

/// V2 修改邮箱页（已绑定邮箱的用户更换邮箱）。
///
/// 四步流程：
/// 1. 展示当前（旧）邮箱，向旧邮箱发送验证码
/// 2. 校验旧邮箱验证码
/// 3. 输入新邮箱，向新邮箱发送验证码
/// 4. 校验新邮箱验证码并完成
///
/// 注意：发送 / 校验验证码的后端接口尚未提供，
/// 当前网络请求处均为占位（TODO），UI 与交互已完整。
class ChangeEmailV2 extends StatefulWidget {
  const ChangeEmailV2({super.key});

  @override
  State<ChangeEmailV2> createState() => _ChangeEmailV2State();
}

class _ChangeEmailV2State extends State<ChangeEmailV2> {
  _ChangeStep _step = _ChangeStep.oldEmail;

  final TextEditingController _oldEmailController = TextEditingController();
  final TextEditingController _oldCodeController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _newCodeController = TextEditingController();

  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentEmail();
  }

  Client get client => Matrix.of(context).client;

  @override
  void dispose() {
    _oldEmailController.dispose();
    _oldCodeController.dispose();
    _newEmailController.dispose();
    _newCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentEmail() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final pids = await client.getAccount3PIDs();
      final email = pids
          ?.where((p) => p.medium == ThirdPartyIdentifierMedium.email)
          .toList();
      if (email?.isNotEmpty == true) {
        _oldEmailController.text = email!.first.address;
      }
    } catch (_) {
      // 忽略，邮箱留空
    }
  }

  /// 1. 向旧邮箱发送验证码
  Future<void> _sendOldCode() async {
    final l10n = L10n.of(context);
    final email = _oldEmailController.text.trim();
    if (!email.isEmail) {
      v2ShowFormHint(context, l10n.enterValidEmail);
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 调用后端「向旧邮箱发送验证码」接口，入参 oldEmail。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _ChangeStep.oldCode;
    });
  }

  /// 2. 校验旧邮箱验证码
  Future<void> _verifyOldCode() async {
    final l10n = L10n.of(context);
    if (_oldCodeController.text.trim().isEmpty) {
      v2ShowFormHint(
        context,
        '${l10n.pleaseFillOut} ${l10n.verificationCode}',
      );
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 调用后端「校验旧邮箱验证码」接口，入参 oldEmail + code。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _ChangeStep.newEmail;
    });
  }

  /// 3. 向新邮箱发送验证码
  Future<void> _sendNewCode() async {
    final l10n = L10n.of(context);
    final email = _newEmailController.text.trim();
    if (!email.isEmail) {
      v2ShowFormHint(context, l10n.enterValidEmail);
      return;
    }
    if (email == _oldEmailController.text.trim()) {
      v2ShowFormHint(context, l10n.newEmailSameAsOld);
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 调用后端「向新邮箱发送验证码」接口，入参 newEmail。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _ChangeStep.newCode;
    });
  }

  /// 4. 校验新邮箱验证码并完成
  Future<void> _verifyNewCode() async {
    final l10n = L10n.of(context);
    if (_newCodeController.text.trim().isEmpty) {
      v2ShowFormHint(
        context,
        '${l10n.pleaseFillOut} ${l10n.verificationCode}',
      );
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 校验通过后将账户邮箱更换为 newEmail，入参 oldEmail + oldCode + newEmail + newCode。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _busy = false);
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    _loadCurrentEmail();
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
                  _ChangeStep.oldEmail => _buildOldEmailStep(l10n),
                  _ChangeStep.oldCode => _buildOldCodeStep(l10n),
                  _ChangeStep.newEmail => _buildNewEmailStep(l10n),
                  _ChangeStep.newCode => _buildNewCodeStep(l10n),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 步骤一：修改邮箱（旧邮箱只读）
  Widget _buildOldEmailStep(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FormHeader(
          icon: Icons.markunread_outlined,
          title: l10n.changeEmail,
          description: l10n.changeEmailDescription,
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.email),
        SizedBox(height: 8),
        V2TextInput(
          controller: _oldEmailController,
          hint: '',
          readOnly: true,
        ),
        SizedBox(height: 32),
        V2PrimaryButton(
          label: l10n.getVerificationCode,
          busy: _busy,
          onTap: _sendOldCode,
        ),
      ],
    );
  }

  /// 步骤二：输入旧邮箱验证码
  Widget _buildOldCodeStep(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FormHeader(
          icon: Icons.markunread_outlined,
          title: l10n.bindEmail,
          description: l10n.enterCodeSentTo(_oldEmailController.text.trim()),
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.verificationCode),
        SizedBox(height: 8),
        V2TextInput(
          controller: _oldCodeController,
          hint: l10n.enterVerificationCode,
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: 32),
        V2PrimaryButton(
          label: l10n.next,
          busy: _busy,
          onTap: _verifyOldCode,
        ),
      ],
    );
  }

  /// 步骤三：绑定新邮箱
  Widget _buildNewEmailStep(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FormHeader(
          icon: Icons.markunread_outlined,
          title: l10n.bindNewEmail,
          description: l10n.changeEmailDescription,
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.email),
        SizedBox(height: 8),
        V2TextInput(
          controller: _newEmailController,
          hint: l10n.enterEmail,
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: 32),
        V2PrimaryButton(
          label: l10n.getVerificationCode,
          busy: _busy,
          onTap: _sendNewCode,
        ),
      ],
    );
  }

  /// 步骤四：输入新邮箱验证码
  Widget _buildNewCodeStep(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FormHeader(
          icon: Icons.markunread_outlined,
          title: l10n.bindNewEmail,
          description: l10n.enterCodeSentTo(_newEmailController.text.trim()),
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.verificationCode),
        SizedBox(height: 8),
        V2TextInput(
          controller: _newCodeController,
          hint: l10n.enterVerificationCode,
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: 32),
        V2PrimaryButton(
          label: l10n.done,
          busy: _busy,
          onTap: _verifyNewCode,
        ),
      ],
    );
  }
}
