import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/oidc_session_json_extension.dart';
import 'package:fluffychat/utils/sign_in_flows/check_homeserver.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_login_scaffold.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:matrix/msc_extensions/msc_2964_oidc_login_flow/msc_2964_oidc_login_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/universal_html.dart' as web;

/// V2 欢迎页（登录入口）。
///
/// 合并原 [IntroPagePresenter] 的业务逻辑与 [IntroPage] 的 V2 视图，
/// 统一放在 pages_v2 下。保留 OIDC 登录回调、预设 homeserver 直连、
/// 跳转 sign_in / sign_up 的完整流程。
class IntroV2 extends StatefulWidget {
  const IntroV2({super.key});

  @override
  State<IntroV2> createState() => _IntroV2State();
}

class _IntroV2State extends State<IntroV2> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) _finishOidcLogin();
  }

  /// [connectToHomeserverFlow] 状态回调：成功时关闭全局加载层，
  /// 失败时由 flow 内部自行 [V2Toast.show] 错误提示。
  void _onConnectStateChanged(AsyncSnapshot<bool> snapshot) {
    if (snapshot.connectionState == ConnectionState.done &&
        !snapshot.hasError) {
      V2Toast.dismiss();
    }
  }

  Future<void> _finishOidcLogin() async {
    final store = await SharedPreferences.getInstance();
    final storedHomeserverString = store.getString(
      OidcSessionJsonExtension.homeserverStoreKey,
    );
    final homeserverUrl = storedHomeserverString == null
        ? null
        : Uri.tryParse(storedHomeserverString);

    final oidcSessionString = store.getString(
      OidcSessionJsonExtension.storeKey,
    );
    final session = oidcSessionString == null
        ? null
        : OidcSessionJsonExtension.fromJson(jsonDecode(oidcSessionString));

    await store.remove(OidcSessionJsonExtension.storeKey);
    await store.remove(OidcSessionJsonExtension.homeserverStoreKey);
    if (!mounted) return;

    if (homeserverUrl == null || session == null) return;

    V2Toast.loading(L10n.of(context).logInTo(homeserverUrl.origin));

    try {
      final returnUrl = Uri.parse(web.window.location.href);
      final queryParameters = returnUrl.hasFragment
          ? Uri.parse(returnUrl.fragment).queryParameters
          : returnUrl.queryParameters;
      final code = queryParameters['code'] as String;
      final state = queryParameters['state'] as String;

      final client = await Matrix.of(context).getLoginClient();
      await client.checkHomeserver(homeserverUrl);
      await client.oidcLogin(session: session, code: code, state: state);
      if (!mounted) return;
      V2Toast.dismiss();
      context.go('/backup');
    } catch (e, s) {
      Logs().w('Unable to login via OIDC', e, s);
      if (mounted) {
        V2Toast.dismiss();
        V2Toast.show(e.toLocalizedString(context));
      }
    }
  }

  void _login() {
    final presetHomeserver = AppSettings.presetHomeserver.value;
    if (presetHomeserver.isEmpty) {
      context.go('${GoRouterState.of(context).uri.path}/sign_in');
      return;
    }
    V2Toast.loading(L10n.of(context).logInTo(presetHomeserver));
    connectToHomeserverFlow(
      PublicHomeserverData(name: presetHomeserver),
      context,
      _onConnectStateChanged,
      false,
    );
  }

  void _signUp() {
    final presetHomeserver = AppSettings.presetHomeserver.value;
    if (presetHomeserver.isEmpty) {
      context.go('${GoRouterState.of(context).uri.path}/sign_up');
      return;
    }
    V2Toast.loading(L10n.of(context).logInTo(presetHomeserver));
    connectToHomeserverFlow(
      PublicHomeserverData(name: presetHomeserver),
      context,
      _onConnectStateChanged,
      true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final v2 = V2Theme.of(context);
    final appName = AppSettings.applicationName.value;
    final welcomeText = AppSettings.welcomeText.value.isEmpty
        ? null
        : AppSettings.welcomeText.value;

    return V2LoginScaffold(
      child: Scaffold(
        backgroundColor: v2.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Logo
              Center(
                child: Hero(
                  tag: 'info-logo',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(120),
                    child: Image.asset(
                      'assets/logo/mini/logo_mini.png',
                      width: 120,
                      height: 120,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // 标题
              Text(
                l10n.loginWelcomeTitle(appName),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              // 副标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  welcomeText ?? l10n.loginWelcomeSubtitle(appName),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: v2.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(flex: 3),
              // 按钮区
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GradientButton(
                      label: l10n.login,
                      onTap: _login,
                    ),
                    // const SizedBox(height: 16),
                    // _OutlineButton(
                    //   label: l10n.createAccount,
                    //   onTap: _signUp,
                    // ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

/// 渐变主按钮（登录）
class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GradientButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B4A), Color(0xFFFF8A5C)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B4A).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 浅色描边按钮（创建账户）
class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: v2.accentLight,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: v2.accent.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: v2.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
