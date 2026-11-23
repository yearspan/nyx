import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

extension UiaRequestManager on MatrixState {
  /// 委托式 OIDC（MSC4198）服务器用该 stage 要求用户在外部账户管理
  /// 界面中确认重置交叉签名密钥，而不是走老式 homeserver fallback。
  static const crossSigningResetStage = 'org.matrix.cross_signing_reset';

  /// 打开外部认证页面，用户完成后回到 App 再向服务器提交该 stage。
  ///
  /// context 在调用点可能已经跨越 async 间隙，因此这里统一从全局
  /// navigatorKey 实时获取，避免 use_build_context_synchronously。
  Future<void> _launchAuthAndComplete({
    required UiaRequest uiaRequest,
    required Uri url,
    required String? completedType,
  }) async {
    final l10n = L10n.of(context);
    final navigatorContext =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
        context;
    final confirmed = await V2ConfirmDialog.show(
      navigatorContext,
      title: l10n.warning,
      message: l10n.pleaseFollowInstructionsOnWeb,
      confirmLabel: l10n.open,
      cancelLabel: l10n.cancel,
    );
    if (confirmed != true) return uiaRequest.cancel(UiaCanceledException());

    launchUrl(url, mode: LaunchMode.inAppBrowserView);
    final completer = Completer();
    final listener = AppLifecycleListener(onResume: completer.complete);
    await completer.future;
    listener.dispose();

    return await uiaRequest.completeStage(
      AuthenticationData(
        session: uiaRequest.session,
        type: completedType,
      ),
    );
  }

  Future uiaRequestHandler(UiaRequest uiaRequest) async {
    final l10n = L10n.of(context);
    final navigatorContext =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
        context;
    try {
      if (uiaRequest.state != UiaRequestState.waitForUser ||
          uiaRequest.nextStages.isEmpty) {
        Logs().d('Uia Request Stage: ${uiaRequest.state}');
        return;
      }
      // 服务器可能同时下发多条 flow，优先选择客户端能直接处理的 stage，
      // 避免盲目取 first 落到无法处理的外部网页。
      const preferredStages = [
        AuthenticationTypes.password,
        AuthenticationTypes.dummy,
        crossSigningResetStage,
      ];
      final stage = preferredStages.firstWhere(
        uiaRequest.nextStages.contains,
        orElse: () => uiaRequest.nextStages.first,
      );
      Logs().d('Uia Request Stage: $stage');
      switch (stage) {
        case AuthenticationTypes.password:
          final input =
              cachedPassword ??
              (await showTextInputDialog(
                context: navigatorContext,
                title: l10n.pleaseEnterYourPassword,
                okLabel: l10n.ok,
                cancelLabel: l10n.cancel,
                minLines: 1,
                maxLines: 1,
                obscureText: true,
                hintText: '******',
              ));
          if (input == null || input.isEmpty) {
            return uiaRequest.cancel();
          }
          return await uiaRequest.completeStage(
            AuthenticationPassword(
              session: uiaRequest.session,
              password: input,
              identifier: AuthenticationUserIdentifier(user: client.userID!),
            ),
          );
        case AuthenticationTypes.dummy:
          return await uiaRequest.completeStage(
            AuthenticationData(
              type: AuthenticationTypes.dummy,
              session: uiaRequest.session,
            ),
          );
        case crossSigningResetStage:
          // MSC4198：打开 MAS 的账户管理地址并带上重置动作，
          // 用户在网页确认后回到 App，由服务器签发新的交叉签名密钥。
          Uri? managementUri;
          try {
            managementUri = (await client.getAuthMetadata())
                .accountManagementUri;
          } catch (e, s) {
            Logs().w('Unable to read account management URI', e, s);
          }
          if (managementUri == null) {
            Logs().w(
              'Server requested cross-signing reset but provided no '
              'account_management_uri',
            );
            return uiaRequest.cancel(
              UiaException('No account management URI available'),
            );
          }
          final resetUrl = managementUri.replace(
            queryParameters: {
              ...managementUri.queryParameters,
              'action': crossSigningResetStage,
            },
          );
          // await 之后重新解析导航 context，避免跨 async 间隙使用旧 context
          return await _launchAuthAndComplete(
            uiaRequest: uiaRequest,
            url: resetUrl,
            completedType: crossSigningResetStage,
          );
        default:
          final stageUrl = uiaRequest.params
              .tryGetMap<String, Object?>(stage)
              ?.tryGet<String>('url');
          final fallbackUrl = client.homeserver!.replace(
            path: '/_matrix/client/v3/auth/$stage/fallback/web',
            queryParameters: {'session': uiaRequest.session},
          );
          final url = stageUrl != null
              ? (Uri.tryParse(stageUrl) ?? fallbackUrl)
              : fallbackUrl;

          return await _launchAuthAndComplete(
            uiaRequest: uiaRequest,
            url: url,
            completedType: stageUrl == null ? null : stage,
          );
      }
    } catch (e, s) {
      Logs().e('Error while background UIA', e, s);
      return uiaRequest.cancel(e is Exception ? e : Exception(e));
    }
  }
}

class UiaException implements Exception {
  final String reason;

  UiaException(this.reason);

  @override
  String toString() => reason;
}

/// 用户主动取消了本次 UIA（如点了「取消」按钮）。
/// 上层应将此视为正常退出，而非错误上报。
class UiaCanceledException implements Exception {
  @override
  String toString() => 'UIA request canceled by user';
}
