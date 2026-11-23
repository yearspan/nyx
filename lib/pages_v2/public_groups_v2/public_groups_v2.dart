import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/public_groups_v2/public_groups_v2_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

/// 公群分类类型
enum PublicGroupType { tech, marketing, web3, crossBorder, freelance }

/// 公群分类数据
class PublicGroupCategory {
  final PublicGroupType type;
  final int count;
  final IconData icon;
  final Color color;

  const PublicGroupCategory({
    required this.type,
    required this.count,
    required this.icon,
    required this.color,
  });
}

/// V2 公群页（Page）
class PublicGroupsV2 extends StatefulWidget {
  const PublicGroupsV2({super.key});

  @override
  PublicGroupsV2Controller createState() => PublicGroupsV2Controller();
}

class PublicGroupsV2Controller extends State<PublicGroupsV2>
    with TickerProviderStateMixin {
  final TextEditingController searchController = TextEditingController();

  /// 公群分类（数量暂为 0，后续从服务器拉取）
  final List<PublicGroupCategory> categories = const [
    PublicGroupCategory(
      type: PublicGroupType.tech,
      count: 0,
      icon: Icons.code,
      color: Color(0xFF3B82F6), // 蓝
    ),
    PublicGroupCategory(
      type: PublicGroupType.marketing,
      count: 0,
      icon: Icons.campaign,
      color: Color(0xFF22C55E), // 绿
    ),
    PublicGroupCategory(
      type: PublicGroupType.web3,
      count: 0,
      icon: Icons.currency_bitcoin,
      color: Color(0xFFF97316), // 橙
    ),
    PublicGroupCategory(
      type: PublicGroupType.crossBorder,
      count: 0,
      icon: Icons.language,
      color: Color(0xFF8B5CF6), // 紫
    ),
    PublicGroupCategory(
      type: PublicGroupType.freelance,
      count: 0,
      icon: Icons.shopping_bag,
      color: Color(0xFFEF4444), // 红
    ),
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  /// 点击分类 → 跳转到该分类的公群列表页（目前为空列表占位，后续从服务器拉取）
  void onCategoryTap(PublicGroupCategory category) {
    context.push('/v2/public-groups/${category.type.name}');
  }

  /// 取分类的本地化名称
  static String localizedName(PublicGroupType type, L10n l10n) {
    return switch (type) {
      PublicGroupType.tech => l10n.publicGroupTech,
      PublicGroupType.marketing => l10n.publicGroupMarketing,
      PublicGroupType.web3 => l10n.publicGroupWeb3,
      PublicGroupType.crossBorder => l10n.publicGroupCrossBorder,
      PublicGroupType.freelance => l10n.publicGroupFreelance,
    };
  }

  @override
  Widget build(BuildContext context) => PublicGroupsV2View(this);
}
