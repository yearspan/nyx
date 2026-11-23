import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

/// V2 长按/右键上下文菜单项
class V2ContextMenuItem {
  /// 唯一标识（可选），用于在返回结果中区分点击的项，避免依赖本地化 label 做判断
  final String? id;
  final String label;
  final IconData icon;
  final String? img;
  final VoidCallback? onTap;

  /// 是否为危险操作（删除等），显示红色
  final bool isDestructive;

  /// 是否显示选中对勾（用于单选型菜单，如自动删除时长）
  final bool checked;

  const V2ContextMenuItem({
    this.id,
    required this.label,
    required this.icon,
    this.onTap,
    this.isDestructive = false,
    this.checked = false, 
    this.img,
  });
}

/// V2 风格的上下文菜单（白底圆角、左侧图标、右侧箭头）。
///
/// 通过 [V2ContextMenu.show] 在长按/点击位置弹出，复用同一套样式，
/// 后续要改外观只需改这一处。实现上与聊天页 + 号菜单一致，采用
/// OverlayEntry 锚定卡片 + 缩放淡入动画，而非 Material 默认的 showMenu。
class V2ContextMenu {
  /// 在 [position]（全局坐标）处弹出菜单，返回被点击的项（null 表示取消）。
  static Future<V2ContextMenuItem?> show(
    BuildContext context, {
    required List<V2ContextMenuItem> items,
    required Offset position,
  }) {
    final completer = Completer<V2ContextMenuItem?>();
    final overlayState = Overlay.of(context, rootOverlay: true);
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    const menuWidth = 180.0;
    const menuItemHeight = 48.0;
    final menuHeight = menuItemHeight * items.length + 16.0; // 上下内边距

    // 水平方向：让菜单中心贴近按下点，并夹在屏幕内
    var left = position.dx - menuWidth / 2;
    left = left.clamp(8.0, screenSize.width - menuWidth - 8.0);

    // 垂直方向：优先显示在按下点上方，空间不足则显示在下方
    var top = position.dy - menuHeight - 12;
    if (top < mediaQuery.padding.top + 8) {
      top = position.dy + 24;
    }
    top = top.clamp(
      mediaQuery.padding.top + 8,
      screenSize.height - menuHeight - mediaQuery.padding.bottom - 8,
    );

    late OverlayEntry overlay;
    void close([V2ContextMenuItem? item]) {
      if (!completer.isCompleted) completer.complete(item);
      overlay.remove();
    }

    overlay = OverlayEntry(
      builder: (_) {
        return Stack(
          children: [
            // 半透明遮罩：点击外部关闭
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => close(null),
              ),
            ),
            // 锚定在按下位置附近的圆角卡片
            Positioned(
              left: left,
              top: top,
              child: _AnimatedMenuCard(
                items: items,
                onItemTap: close,
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(overlay);
    return completer.future;
  }
}

/// 带缩放+淡入动画的菜单卡片，样式与聊天页 + 号菜单一致
class _AnimatedMenuCard extends StatefulWidget {
  final List<V2ContextMenuItem> items;
  final void Function(V2ContextMenuItem item) onItemTap;

  const _AnimatedMenuCard({required this.items, required this.onItemTap});

  @override
  State<_AnimatedMenuCard> createState() => _AnimatedMenuCardState();
}

class _AnimatedMenuCardState extends State<_AnimatedMenuCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.center,
        child: Material(
          color: v2.cardBackground,
          elevation: 12,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 180,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.items
                    .map(
                      (item) => InkWell(
                        onTap: () => widget.onItemTap(item),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              item.img != null
                                  ? Image.asset(item.img!, width: 26)
                                  : Icon(
                                      item.icon,
                                      size: 22,
                                      color: item.isDestructive
                                          ? Color(0xFFFF3B30)
                                          : onSurface,
                                    ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: item.isDestructive
                                        ? Color(0xFFFF3B30)
                                        : onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item.checked)
                                Padding(
                                  padding: EdgeInsets.only(left: 12),
                                  child: Icon(
                                    Icons.check,
                                    size: 20,
                                    color: v2.accent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
