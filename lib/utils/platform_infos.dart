import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../config/app_config.dart';

abstract class PlatformInfos {
  static bool get isWeb => kIsWeb;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get isCupertinoStyle => isIOS || isMacOS;

  static bool get isMobile => isAndroid || isIOS;

  /// For desktops which don't support ChachedNetworkImage yet
  static bool get isBetaDesktop => isWindows || isLinux;

  static bool get isDesktop => isLinux || isWindows || isMacOS;

  /// macOS 与 iOS：用于需要确定上传进度条的场景（其余平台回退为
  /// 不确定转圈）。
  static bool get isMacOSOrIOS => isMacOS || isIOS;

  static bool get usesTouchscreen => !isMobile;

  // video_player (原生) 覆盖 Android/iOS/macOS/web，
  // Windows/Linux 由 video_player_media_kit 提供支持，见 main.dart。
  static bool get supportsVideoPlayer => true;

  static bool get supportsCustomImageResizer =>
      PlatformInfos.isWeb || PlatformInfos.isMobile;

  /// Web could also record in theory but currently creates broken opus
  static bool get platformCanRecord => (isMobile || isMacOS);

  static bool get supportsAppLock => (isMobile || isMacOS);

  static String get appDisplayName =>
      '${AppSettings.applicationName.value} ${isWeb ? 'web' : Platform.operatingSystem}${kReleaseMode ? '' : 'Debug'}';

  static Future<String> getVersion() async {
    var version = kIsWeb ? 'Web' : 'Unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    return version;
  }

  static Future<void> showDialog(BuildContext context) async {
    final l10n = L10n.of(context);
    final version = await PlatformInfos.getVersion();
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      children: [
        Text(l10n.versionWithNumber(version)),
        TextButton.icon(
          onPressed: () => launchUrlString(AppConfig.sourceCodeUrl),
          icon: const Icon(Icons.source_outlined),
          label: Text(l10n.sourceCode),
        ),
        Builder(
          builder: (innerContext) {
            return TextButton.icon(
              onPressed: () {
                context.go('/logs');
                Navigator.of(innerContext).pop();
              },
              icon: const Icon(Icons.list_outlined),
              label: Text(l10n.logs),
            );
          },
        ),
        Builder(
          builder: (innerContext) {
            return TextButton.icon(
              onPressed: () {
                context.go('/configs');
                Navigator.of(innerContext).pop();
              },
              icon: const Icon(Icons.settings_applications_outlined),
              label: Text(l10n.advancedConfigs),
            );
          },
        ),
      ],
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(64),
        child: Image.asset(
          './assets/logo/mini/logo_mini.png',
          width: 64,
          height: 64,
        ),
      ),
      applicationName: AppSettings.applicationName.value,
    );
  }
}
