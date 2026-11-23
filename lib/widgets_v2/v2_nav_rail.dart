import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

import 'v2_bottom_nav.dart';

/// V2 宽屏（平板/桌面/Web）导航栏（左侧垂直 Rail）
class V2NavRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<V2NavItem> items;

  const V2NavRail({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    return Container(
      width: FluffyThemes.navRailWidth,
      decoration: BoxDecoration(
        color: v2.cardBackground,
        border: Border(right: BorderSide(color: v2.divider)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = index == currentIndex;
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: InkWell(
                      onTap: () => onTap(index),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected ? v2.accentLight : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              "assets/images/main/${item.icon}.png",
                              color: selected ? v2.accent : v2.textSecondary,
                              width: 30,
                            ),
                            SizedBox(height: 6),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: selected ? v2.accent : v2.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
