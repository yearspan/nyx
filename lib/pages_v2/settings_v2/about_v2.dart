import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// V2 关于页
class AboutV2 extends StatefulWidget {
  const AboutV2({super.key});

  @override
  State<AboutV2> createState() => _AboutV2State();
}

class _AboutV2State extends State<AboutV2> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = await PlatformInfos.getVersion();
    if (mounted) setState(() => _version = v);
  }

  String get _appName => AppSettings.applicationName.value;

  void _openUrl(String url) {
    launchUrlString(url, mode: LaunchMode.inAppBrowserView);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.about),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 顶部 App 信息
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/logo/mini/logo_mini.png',
                      width: 84,
                      height: 84,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    _appName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _version != null
                        ? l10n.versionWithNumber(_version!)
                        : '',
                    style: TextStyle(
                      fontSize: 13,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),

                  SizedBox(height: 32),
                  // 功能列表
                  // _Card(
                  //   children: [
                  //     _NavTile(
                  //       icon: Icons.info_outline,
                  //       iconBg: Color(0xFFDBEAFE),
                  //       iconColor: Color(0xFF3B82F6),
                  //       title: l10n.version,
                  //       trailing: _version ?? '-',
                  //       onTap: () {},
                  //     ),
                  //     const _Line(),
                  //     _NavTile(
                  //       icon: Icons.article_outlined,
                  //       iconBg: Color(0xFFE6F9F9),
                  //       iconColor: V2Theme.of(context).accent,
                  //       title: l10n.changelog,
                  //       onTap: () => _openUrl(AppConfig.changelogUrl),
                  //     ),
                  //     const _Line(),
                  //     _NavTile(
                  //       icon: Icons.source_outlined,
                  //       iconBg: Color(0xFFF3E8FF),
                  //       iconColor: Color(0xFF8B5CF6),
                  //       title: l10n.sourceCode,
                  //       onTap: () => _openUrl(AppConfig.sourceCodeUrl),
                  //     ),
                  //     const _Line(),
                  //     _NavTile(
                  //       icon: Icons.help_outline,
                  //       iconBg: Color(0xFFFFEDD5),
                  //       iconColor: Color(0xFFF97316),
                  //       title: l10n.help,
                  //       onTap: () => _openUrl(AppConfig.supportUrl),
                  //     ),
                  //   ],
                  // ),
                  // SizedBox(height: 16),
                  // _Card(
                  //   children: [
                  //     _NavTile(
                  //       icon: Icons.list_outlined,
                  //       iconBg: Color(0xFFE5E7EB),
                  //       iconColor: Color(0xFF6B7280),
                  //       title: l10n.logs,
                  //       onTap: () => context.push('/logs'),
                  //     ),
                  //     const _Line(),
                  //     _NavTile(
                  //       icon: Icons.settings_applications_outlined,
                  //       iconBg: Color(0xFFE5E7EB),
                  //       iconColor: Color(0xFF6B7280),
                  //       title: l10n.advancedConfigs,
                  //       onTap: () => context.push('/configs'),
                  //     ),
                  //   ],
                  // ),
                  SizedBox(height: 32),
                  // 底部版权
                  Text(
                    '© ${DateTime
                        .now()
                        .year} $_appName',
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),

                  SizedBox(height: 80,),
                ]
            ),

          ),
        ],
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
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
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
