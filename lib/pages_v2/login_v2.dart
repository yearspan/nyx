import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:fluffychat/widgets_v2/v2_login_scaffold.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2 登录页（输入用户名 / 密码）。
///
/// 复用原有 [Login] 控制器的全部业务逻辑，仅将 UI 重构为 V2 风格，
/// 优先复用 [V2AppBar] / [V2TextInput] / [V2VisibilityToggle] /
/// [V2PrimaryButton] 等公共组件。
class LoginV2 extends StatefulWidget {
  final Client client;
  const LoginV2({required this.client, super.key});

  @override
  State<LoginV2> createState() => _LoginV2State();
}

class _LoginV2State extends State<LoginV2> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String? usernameError;
  String? passwordError;
  bool loading = false;
  bool showPassword = false;

  void toggleShowPassword() =>
      setState(() => showPassword = !loading && !showPassword);

  Future<void> login() async {
    final matrix = Matrix.of(context);
    if (usernameController.text.isEmpty) {
      setState(() => usernameError = L10n.of(context).pleaseEnterYourUsername);
    } else {
      setState(() => usernameError = null);
    }
    if (passwordController.text.isEmpty) {
      setState(() => passwordError = L10n.of(context).pleaseEnterYourPassword);
    } else {
      setState(() => passwordError = null);
    }

    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      return;
    }

    setState(() => loading = true);

    _coolDown?.cancel();

    try {
      final username = usernameController.text;
      AuthenticationIdentifier identifier;
      if (username.isEmail) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'email',
          address: username,
        );
      } else if (username.isPhoneNumber) {
        identifier = AuthenticationThirdPartyIdentifier(
          medium: 'msisdn',
          address: username,
        );
      } else {
        identifier = AuthenticationUserIdentifier(user: username);
      }
      final client = await matrix.getLoginClient();
      await client.login(
        LoginType.mLoginPassword,
        identifier: identifier,
        // To stay compatible with older server versions
        // ignore: deprecated_member_use
        user: identifier.type == AuthenticationIdentifierTypes.userId
            ? username
            : null,
        password: passwordController.text,
        initialDeviceDisplayName: PlatformInfos.appDisplayName,
      );
      if (mounted) {
        V2Toast.dismiss();
        context.go('/backup');
      }
    } on MatrixException catch (exception) {
      setState(() => passwordError = exception.errorMessage);
      return setState(() => loading = false);
    } catch (exception) {
      setState(() => passwordError = exception.toString());
      return setState(() => loading = false);
    }

    if (mounted) setState(() => loading = false);
  }

  Timer? _coolDown;

  void checkWellKnownWithCoolDown(String userId) {
    _coolDown?.cancel();
    _coolDown = Timer(
      const Duration(seconds: 1),
      () => _checkWellKnown(userId),
    );
  }

  Future<void> _checkWellKnown(String userId) async {
    if (mounted) setState(() => usernameError = null);
    if (!userId.isValidMatrixIdStrict()) return;
    final oldHomeserver = widget.client.homeserver;
    try {
      var newDomain = Uri.https(userId.domain!, '');
      widget.client.homeserver = newDomain;
      DiscoveryInformation? wellKnownInformation;
      try {
        wellKnownInformation = await widget.client.getWellknown();
        if (wellKnownInformation.mHomeserver.baseUrl.toString().isNotEmpty) {
          newDomain = wellKnownInformation.mHomeserver.baseUrl;
        }
      } catch (_) {
        // do nothing, newDomain is already set to a reasonable fallback
      }
      if (newDomain != oldHomeserver) {
        await widget.client.checkHomeserver(newDomain);

        if (widget.client.homeserver == null) {
          widget.client.homeserver = oldHomeserver;
          // okay, the server we checked does not appear to be a matrix server
          Logs().v(
            '$newDomain is not running a homeserver, asking to use $oldHomeserver',
          );
          if (!mounted) return;
          final l10n = L10n.of(context);
          final dialogResult = await showOkCancelAlertDialog(
            context: context,
            useRootNavigator: false,
            title: l10n.noMatrixServer(
              newDomain.toString(),
              oldHomeserver.toString(),
            ),
            okLabel: l10n.ok,
            cancelLabel: l10n.cancel,
          );
          if (!mounted) return;
          if (dialogResult == OkCancelResult.ok) {
            if (mounted) setState(() => usernameError = null);
          } else {
            Navigator.of(context, rootNavigator: false).pop();
            return;
          }
        }
        usernameError = null;
        if (mounted) setState(() {});
      } else {
        widget.client.homeserver = oldHomeserver;
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      widget.client.homeserver = oldHomeserver;
      if (!mounted) return;
      usernameError = e.toLocalizedString(context);
      if (mounted) setState(() {});
    }
  }

  Future<void> passwordForgotten() async {
    final l10n = L10n.of(context);
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.enterAnEmailAddress,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: usernameController.text.isEmail
          ? usernameController.text
          : '',
      hintText: l10n.enterAnEmailAddress,
      keyboardType: TextInputType.emailAddress,
    );
    if (input == null) return;
    if (!mounted) return;
    final clientSecret = DateTime.now().millisecondsSinceEpoch.toString();
    final response = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.requestTokenToResetPasswordEmail(
        clientSecret,
        input,
        sendAttempt++,
      ),
    );
    if (response.error != null) return;
    if (!mounted) return;
    final password = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.passwordForgotten,
      message: l10n.chooseAStrongPassword,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: '******',
      obscureText: true,
      minLines: 1,
      maxLines: 1,
    );
    if (password == null) return;
    if (!mounted) return;
    final ok = await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.weSentYouAnEmail,
      message: l10n.pleaseClickOnLink,
      okLabel: l10n.iHaveClickedOnLink,
    );
    if (ok != OkCancelResult.ok) return;
    if (!mounted) return;
    final data = <String, dynamic>{
      'new_password': password,
      'logout_devices': false,
      'auth': AuthenticationThreePidCreds(
        type: AuthenticationTypes.emailIdentity,
        threepidCreds: ThreepidCreds(
          sid: response.result!.sid,
          clientSecret: clientSecret,
        ),
      ).toJson(),
    };
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => widget.client.request(
        RequestType.POST,
        '/client/v3/account/password',
        data: data,
      ),
    );
    if (!mounted) return;
    if (success.error == null) {
      V2Toast.show(l10n.passwordHasBeenChanged);
      usernameController.text = input;
      passwordController.text = password;
      login();
    }
  }

  static int sendAttempt = 0;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final v2 = V2Theme.of(context);
    final homeserver = widget.client.homeserver?.toString().replaceFirst(
      'https://',
      '',
    );
    final title = homeserver == null
        ? l10n.loginWithMatrixId
        : l10n.logInTo(homeserver);

    return V2LoginScaffold(
      child: Scaffold(
        backgroundColor: v2.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              V2AppBar(title: title),
              Expanded(
                child: AutofillGroup(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Center(
                          child: Hero(
                            tag: 'info-logo',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(128),
                              child: Image.asset(
                                'assets/logo/mini/logo_mini.png',
                                width: 96,
                                height: 96,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // 用户名
                        V2FieldLabel(l10n.matrixId),
                        const SizedBox(height: 8),
                        V2TextInput(
                          controller: usernameController,
                          hint: '@username:domain',
                          readOnly: loading,
                          autocorrect: false,
                          autofocus: true,
                          onChanged: checkWellKnownWithCoolDown,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: loading
                              ? null
                              : [AutofillHints.username],
                        ),
                        if (usernameError != null)
                          _ErrorText(text: usernameError!),
                        const SizedBox(height: 20),
                        // 密码
                        V2FieldLabel(l10n.password),
                        const SizedBox(height: 8),
                        V2TextInput(
                          controller: passwordController,
                          hint: '******',
                          obscure: !showPassword,
                          readOnly: loading,
                          autocorrect: false,
                          onSubmitted: (_) => login(),
                          textInputAction: TextInputAction.go,
                          autofillHints: loading
                              ? null
                              : [AutofillHints.password],
                          trailing: V2VisibilityToggle(
                            visible: showPassword,
                            onTap: toggleShowPassword,
                          ),
                        ),
                        if (passwordError != null)
                          _ErrorText(text: passwordError!),
                        const SizedBox(height: 24),
                        V2PrimaryButton(
                          label: l10n.login,
                          busy: loading,
                          onTap: loading ? null : login,
                        ),
                        if (homeserver != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: loading ? null : passwordForgotten,
                              child: Text(l10n.passwordForgotten),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
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

/// 表单错误提示文字
class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
