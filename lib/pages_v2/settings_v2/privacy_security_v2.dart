import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_advanced_switch/flutter_advanced_switch.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets_v2/v2_confirm_dialog.dart';

/// V2 隐私与安全页
class PrivacySecurityV2 extends StatefulWidget {
  const PrivacySecurityV2({super.key});

  @override
  State<PrivacySecurityV2> createState() => _PrivacySecurityV2State();
}

class _PrivacySecurityV2State extends State<PrivacySecurityV2> {
  StreamSubscription<BasicEvent>? _accountDataSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 屏蔽名单变化后刷新数量
      // ignore: deprecated_member_use
      _accountDataSub = Matrix.of(context).client.onAccountData.stream.listen((
        event,
      ) {
        if (event.type == 'm.ignored_user_list' && mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _accountDataSub?.cancel();
    super.dispose();
  }

  Client get client => Matrix.of(context).client;

  /// 分享在线状态 = 同时发送输入通知与已读回执
  bool get _shareOnlineStatus =>
      AppSettings.sendTypingNotifications.value &&
      AppSettings.sendPublicReadReceipts.value;

  Future<void> _setShareOnlineStatus(bool value) async {
    await AppSettings.sendTypingNotifications.setItem(value);
    await AppSettings.sendPublicReadReceipts.setItem(value);
    if (mounted) setState(() {});
  }

  int get blockedCount => client.ignoredUsers.length;

  /// 修改登录密码。
  ///
  /// nstalk 等服务器通过 OIDC（MSC2965）把账号管理委托给了独立的
  /// 认证服务，Matrix 标准的 `POST /account/password` 接口会返回
  /// M_UNRECOGNIZED。此时需要打开 `account_management_uri` 在浏览器中
  /// 完成改密码。若服务器未提供该地址，则回退到应用内改密码页。
  Future<void> _changeLoginPassword() async {
    final client = Matrix.of(context).client;
    Uri? manageUri;
    try {
      final metadata = await client.getAuthMetadata();
      manageUri = metadata.accountManagementUri;
    } catch (_) {
      // 服务器不支持 auth_metadata 或请求失败，走应用内改密码页
    }
    if (!mounted) return;
    if (manageUri != null) {
      await launchUrl(manageUri, mode: LaunchMode.inAppBrowserView);
      return;
    }
    context.push('/v2/settings/password');
  }

  /// 恢复密钥 / 修复加密身份。
  ///
  /// 与原版设置页的 firstRunBootstrapAction 行为一致：
  /// - 在线密钥备份正常（connected）：先弹「重置恢复密钥」确认，
  ///   确认后进入重置流程 /backup?reset=true；
  /// - 备份不可用（如卸载重装后本机密钥对不上、未被交叉签名）：
  ///   直接进入加密引导页 /backup，可在其中用其它设备验证、输入密钥，
  ///   或点「重置账户」直接重置本机加密身份。
  Future<void> _recoveryKeyAction() async {
    final l10n = L10n.of(context);
    bool connected;
    try {
      if (client.prevBatch == null) {
        await client.onSync.stream.first;
      }
      final state = await client.getCryptoIdentityState();
      connected = state.initialized && state.connected;
    } catch (_) {
      // 状态读取失败时按「未连接」处理，进入引导页让用户自行恢复/重置
      connected = false;
    }
    if (!mounted) return;

    if (connected) {
      final confirmed = await V2ConfirmDialog.show(
        context,
        title: l10n.chatBackup,
        message: l10n.onlineKeyBackupEnabled,
        confirmLabel: l10n.resetRecoveryKey,
        cancelLabel: l10n.close,
      );
      if (confirmed != true) return;
      if (!mounted) return;
      await context.push('/backup?reset=true');
      return;
    }
    await context.push('/backup');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.privacyAndSecurity),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: 12, bottom: 40),
              children: [
                // 安全：屏蔽 / 锁屏 / 登录密码 / 恢复密钥
                _Card(
                  children: [
                    _NavTile(
                      icon: Icons.block,
                      iconBg: Color(0xFFFFE0E0),
                      iconColor: Color(0xFFFF3B30),
                      title: l10n.blockedUsers,
                      trailing: '$blockedCount',
                      onTap: () => context.push('/v2/blocked-users'),
                    ),
                    const _Line(),
                    if (PlatformInfos.supportsAppLock)
                      ValueListenableBuilder<bool>(
                        valueListenable:
                            AppLock.of(context).isActiveListenable,
                        builder: (context, active, _) => _NavTile(
                          icon: Icons.lock_outline,
                          iconBg: Color(0xFFFFE9E2),
                          iconColor: V2Theme.of(context).accent,
                          title: l10n.screenLockPasscode,
                          trailing: active ? l10n.turnedOn : null,
                          onTap: () => context.push('/v2/settings/app-lock'),
                        ),
                      ),
                    if (PlatformInfos.supportsAppLock) const _Line(),
                    _NavTile(
                      icon: Icons.lock_open_outlined,
                      iconBg: Color(0xFFDBEAFE),
                      iconColor: Color(0xFF3B82F6),
                      title: l10n.loginPassword,
                      onTap: _changeLoginPassword,
                    ),
                    const _Line(),
                    _NavTile(
                      icon: Icons.vpn_key_outlined,
                      iconBg: Color(0xFFE5E7EB),
                      iconColor: Color(0xFF6B7280),
                      title: l10n.recoveryKey,
                      onTap: _recoveryKeyAction,
                    ),
                  ],
                ),
                SizedBox(height: 24),
                _SectionHeader(l10n.privacy),
                _Card(
                  children: [
                    _SwitchTile(
                      title: l10n.shareOnlineStatus,
                      subtitle: l10n.shareOnlineStatusSubtitle,
                      value: _shareOnlineStatus,
                      onChanged: _setShareOnlineStatus,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          color: V2Theme.of(context).textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      ),
      child: Column(children: children),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: V2Theme.of(context).divider),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color color;
  const _IconBox({
    required this.icon,
    required this.bg,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? trailing;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            _IconBox(icon: icon, bg: iconBg, color: iconColor),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 14,
                  color: V2Theme.of(context).textSecondary,
                ),
              ),
            SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: V2Theme.of(context).textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late final ValueNotifier<bool> _controller;

  @override
  void initState() {
    super.initState();
    _controller = ValueNotifier<bool>(widget.value);
  }

  @override
  void didUpdateWidget(covariant _SwitchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.value != widget.value) {
      _controller.value = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 2),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  SizedBox(height: 3),
                  Text(
                    widget.subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 12),
          AdvancedSwitch(
            controller: _controller,
            activeColor: V2Theme.of(context).accent,
            inactiveColor: Color(0xFFE5E5E5),
            width: 50,
            height: 30,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
            onChanged: (v) => widget.onChanged(v as bool),
          ),
        ],
      ),
    );
  }
}
