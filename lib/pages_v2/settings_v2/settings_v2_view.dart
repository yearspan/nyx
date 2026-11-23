import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/settings_v2/settings_v2.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2 设置视图（View）
class SettingsV2View extends StatelessWidget {
  final SettingsV2Controller controller;
  const SettingsV2View(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final items = controller.settingItems;

    return SingleChildScrollView(
      child: Column(
        children: [
          // 顶部区域（浅灰底 + 操作按钮）
          Container(
            color: V2Theme.of(context).scaffoldBackground,
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // 顶部按钮行
                  Row(
                    children: [
                      // 二维码按钮
                      V2CircleIconButton(
                        icon: Icons.qr_code,
                        size: 38,
                        onTap: controller.onQrTap,
                      ),
                      Spacer(),
                      // 编辑按钮
                      GestureDetector(
                        onTap: controller.onEditTap,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: V2Theme.of(context).cardBackground,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            l10n.edit,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  // 头像 + 名字 + ID（异步加载 profile）
                  FutureBuilder<Profile>(
                    future: controller.profileFuture,
                    builder: (context, snapshot) {
                      final displayName =
                          snapshot.data?.displayName ?? controller.userId;
                      final avatarUrl = snapshot.data?.avatarUrl;
                      return Column(
                        children: [
                          Avatar(
                            mxContent: avatarUrl,
                            name: displayName,
                            size: 80,
                          ),
                          SizedBox(height: 12),
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${controller.userId}',
                            style: TextStyle(
                              fontSize: 13,
                              color: V2Theme.of(context).textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 10),

          // 设置卡片
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: V2Theme.of(context).cardBackground,
                borderRadius: BorderRadius.circular(V2Theme.cardRadius),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => Padding(
                  padding: EdgeInsets.only(left: 60,right: 16),
                  child: Divider(height: 1, color: V2Theme.of(context).divider),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _SettingTile(item: item);
                },
              ),
            ),
          ),

          SizedBox(height: 100),
        ],
      ),
    );
  }
}

/// 设置列表项
class _SettingTile extends StatelessWidget {
  final SettingItem item;
  const _SettingTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 彩色圆角方形图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.iconColor, size: 20),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
                style: TextStyle(
                  fontSize: 13,
                  color: V2Theme.of(context).textSecondary,
                ),
              ),
            SizedBox(width: 4),
            Icon(Icons.chevron_right, color: V2Theme.of(context).textSecondary, size: 22),
          ],
        ),
      ),
    );
  }
}
