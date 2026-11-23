import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

/// V2 移动端底部导航栏（设计稿白色悬浮卡片风格）
class V2BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<V2NavItem> items;

  const V2BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: v2.cardBackground,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final selected = index == currentIndex;
            final onSelected = () => onTap(index);
            return Expanded(
              child: InkWell(
                onTap: onSelected,
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      "assets/images/main/${item.icon}.png",
                      color: selected ? v2.accent : v2.textSecondary,
                      width: 30,
                    ),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected ? v2.accent : v2.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// 导航项数据模型
class V2NavItem {
  final String icon;
  final String label;
  const V2NavItem({required this.icon, required this.label});
}
