import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

/// 长按消息菜单上方的 Telegram 风格快捷回应栏：
/// 一排常用表情 + 末尾「更多表情」入口。
///
/// 宽度固定为 [barWidth]（同时受屏幕宽度约束），内部图标用 Expanded
/// 等分剩余空间，因此在任何约束下都不会产生 Row 溢出。
class QuickReactionBar extends StatelessWidget {
  /// 常用快捷表情（与 Telegram/iOS 信息评价一致）
  static const quickEmojis = ['👍', '❤️', '😂', '😮', '😢'];

  static const barWidth = 236.0;

  /// 我已经对该消息作出的回应 key
  final Set<String> myReactions;

  /// 点击某个表情：已回应则取消，未回应则发送
  final void Function(String emoji) onReact;

  /// 点击「更多表情」
  final VoidCallback onMore;

  const QuickReactionBar({
    super.key,
    required this.myReactions,
    required this.onReact,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final maxAllowed = MediaQuery.of(context).size.width - 24;
    final width = barWidth < maxAllowed ? barWidth : maxAllowed;
    // 用 Material 包裹：本栏浮在菜单卡片（另一颗 Material）之上，
    // 「更多」按钮的 InkWell 水波纹必须有 Material 祖先，否则
    // debugCheckHasMaterial 断言失败
    return Material(
      color: V2Theme.of(context).cardBackground,
      borderRadius: BorderRadius.all(Radius.circular(22)),
      elevation: 12,
      shadowColor: Colors.black26,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Container(
          width: width,
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final emoji in quickEmojis)
                Expanded(
                  child: _ReactionButton(
                    emoji: emoji,
                    selected: myReactions.contains(emoji),
                    onTap: () => onReact(emoji),
                  ),
                ),
              Expanded(child: _MoreButton(onTap: onMore)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionButton extends StatefulWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 1.3 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? V2Theme.of(context).accent.withValues(alpha: 0.15)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            widget.emoji,
            maxLines: 1,
            style: TextStyle(fontSize: 21, height: 1.0),
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        height: 34,
        child: Icon(
          Icons.add_reaction_outlined,
          size: 22,
          color: Color(0xFF8E8E93),
        ),
      ),
    );
  }
}

/// 弹出完整 emoji 选择面板（底部弹层），选中后回调
Future<void> showReactionEmojiPicker(
  BuildContext context, {
  required ValueChanged<String> onEmoji,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: V2Theme.of(context).cardBackground,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            Navigator.of(sheetContext).pop();
            onEmoji(emoji.emoji);
          },
          config: Config(
            locale: Localizations.localeOf(context),
            emojiViewConfig: EmojiViewConfig(
              backgroundColor: V2Theme.of(context).cardBackground,
            ),
            bottomActionBarConfig: const BottomActionBarConfig(
              enabled: false,
            ),
          ),
        ),
      ),
    ),
  );
}
