import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/settings_v2/settings_v2_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// 设置项数据
class SettingItem {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String? subtitle;
  final VoidCallback? onTap;

  const SettingItem({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    this.subtitle,
    this.onTap,
  });
}

/// V2 设置页（Page）
class SettingsV2 extends StatefulWidget {
  const SettingsV2({super.key});

  @override
  SettingsV2Controller createState() => SettingsV2Controller();
}

class SettingsV2Controller extends State<SettingsV2>
    with TickerProviderStateMixin {
  StreamSubscription? _onSyncUpdate;
  StreamSubscription? _onProfileUpdate;

  @override
  void initState() {
    super.initState();
    final client = Matrix.of(context).client;
    _onSyncUpdate = client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _onProfileUpdate = client.onUserProfileUpdate.stream.listen((userId) {
      if (userId == client.userID && mounted) {
        setState(() => _profileFuture = null);
      }
    });
  }

  @override
  void dispose() {
    _onSyncUpdate?.cancel();
    _onProfileUpdate?.cancel();
    super.dispose();
  }

  /// 顶部二维码按钮（占位，后续实现）
  void onQrTap() {
    context.push('/v2/invite-friends');
  }

  /// 顶部编辑按钮
  Future<void> onEditTap() async {
    final updated = await context.push<bool>('/v2/edit-profile');
    if (updated == true && mounted) {
      // 编辑保存成功，重新拉取 profile 以更新头像 / 昵称
      setState(() => _profileFuture = null);
    }
  }

  Client get client => Matrix.of(context).client;

  Future<Profile>? _profileFuture;
  Future<Profile> get profileFuture =>
      _profileFuture ??= client.getProfileFromUserId(client.userID!);

  String get userId => client.userID ?? '';

  /// 设备数量（简略实现：已验证设备数）
  int get deviceCount {
    final keys = client.userDeviceKeys[client.userID]?.deviceKeys.values ?? const [];
    return keys.length;
  }

  /// 当前语言的原生名称
  String get languageName {
    final locale = Localizations.localeOf(context);
    if (locale.scriptCode == 'Hant') return '繁体中文';
    return switch (locale.languageCode) {
      'zh' => '简体中文',
      'en' => 'English',
      _ => locale.languageCode,
    };
  }

  /// 设置项列表
  List<SettingItem> get settingItems {
    final l10n = L10n.of(context);
    return [
      SettingItem(
        title: l10n.notifications,
        icon: Icons.notifications_outlined,
        iconColor: Color(0xFFF97316),
        iconBgColor: Color(0xFFFFEDD5),
        onTap: () => context.push('/v2/notifications'),
      ),
      SettingItem(
        title: l10n.privacyAndSecurity,
        icon: Icons.shield_outlined,
        iconColor: Color(0xFF3B82F6),
        iconBgColor: Color(0xFFDBEAFE),
        onTap: () => context.push('/v2/privacy-security'),
      ),
      SettingItem(
        title: l10n.devices,
        icon: Icons.devices_outlined,
        iconColor: Color(0xFFF97316),
        iconBgColor: Color(0xFFFFEDD5),
        subtitle: deviceCount > 0 ? '$deviceCount' : null,
        onTap: () => context.push('/v2/devices'),
      ),
      SettingItem(
        title: l10n.language,
        icon: Icons.language,
        iconColor: Color(0xFF3B82F6),
        iconBgColor: Color(0xFFDBEAFE),
        subtitle: languageName,
        onTap: () => context.push('/v2/settings/language'),
      ),
      SettingItem(
        title: l10n.appearance,
        icon: Icons.palette_outlined,
        iconColor: Color(0xFF06B6D4),
        iconBgColor: Color(0xFFCFFAFE),
        onTap: () => context.push('/v2/appearance'),
      ),
      SettingItem(
        title: l10n.about,
        icon: Icons.info_outline,
        iconColor: Color(0xFF22C55E),
        iconBgColor: Color(0xFFDCFCE7),
        onTap: () => context.push('/v2/about'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => SettingsV2View(this);
}
