import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/public_groups_v2/public_groups_v2.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets_v2/v2_app_bar.dart';

/// 公群分类列表页（占位：目前显示空列表，后续从服务器拉取数据）
class PublicGroupListV2 extends StatelessWidget {
  final PublicGroupType type;

  const PublicGroupListV2({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final title = PublicGroupsV2Controller.localizedName(type, l10n);

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: title),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 64,
                    color: V2Theme.of(context).textSecondary.withValues(alpha: 0.4),
                  ),
                  SizedBox(height: 16),
                  Text(
                    l10n.noPublicGroupsYet,
                    style: TextStyle(
                      fontSize: 15,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
