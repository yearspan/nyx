import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/public_groups_v2/public_groups_v2.dart';
import 'package:fluffychat/widgets_v2/v2_search_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets_v2/v2_app_bar.dart';

/// V2 公群视图（View）
class PublicGroupsV2View extends StatelessWidget {
  final PublicGroupsV2Controller controller;
  const PublicGroupsV2View(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final categories = controller.categories;

    return Column(
      children: [
        // 顶部 AppBar
        V2AppBar(
          title: l10n.publicGroups,
          showBack: false,
        ),
        // 搜索框
        // V2SearchBar(
        //   controller: controller.searchController,
        //   hintText: l10n.search,
        // ),
        //
        // // 分类列表
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: categories.length,
            separatorBuilder: (_, __) => Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, color: V2Theme.of(context).divider),
            ),
            itemBuilder: (context, index) {
              final category = categories[index];
              return _CategoryTile(
                category: category,
                onTap: () => controller.onCategoryTap(category),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 分类列表项
class _CategoryTile extends StatelessWidget {
  final PublicGroupCategory category;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: category.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(category.icon, color: Colors.white, size: 22),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PublicGroupsV2Controller.localizedName(
                      category.type,
                      l10n,
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    l10n.certifiedGroups(category.count),
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: V2Theme.of(context).textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
