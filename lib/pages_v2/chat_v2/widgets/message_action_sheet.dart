import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/quick_reaction_bar.dart';
import 'package:fluffychat/utils/translation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 长按消息弹出的 iOS 风格操作菜单（浮于消息附近，圆角白色卡片）
class MessageActionSheet {
  /// 在 [anchor]（手指长按位置）附近弹出菜单
  static Future<void> show({
    required BuildContext context,
    required ChatV2Controller controller,
    required Event event,
    required Timeline timeline,
    required Offset anchor,
  }) async {
    final l10n = L10n.of(context);
    final myUserId = controller.sendingClient.userID;
    final isMine = event.senderId == myUserId;

    // 最新一次编辑时间（如有）
    final edits = event.aggregatedEvents(timeline, RelationshipTypes.edit);
    final editedAt = edits.isEmpty ? null : edits.last.originServerTs;

    final canReply = controller.room.canSendDefaultMessages;
    final canCopy = controller.isTextMessage(event) && event.status.isSent;
    final canEdit = controller.canEditEvent(event);
    final canPin = controller.canPinEvents && event.status.isSent;
    final pinned = canPin && controller.isPinned(event);
    final canForward = event.status.isSent;
    final canDelete = controller.canRedactEvent(event);

    // 结束投票：仅投票创建者且投票未结束时显示
    final isPoll = event.type == PollEventContent.startType;
    final canEndPoll = isPoll &&
        isMine &&
        event.status.isSent &&
        !event.getPollHasBeenEnded(timeline);

    // 翻译：仅对方发送的文本消息，且文本语言与当前应用语言不一致时展示
    final canTranslate = canCopy &&
        !isMine &&
        TranslationUtil.isDifferentLanguage(
          event.getDisplayEvent(timeline).body,
          l10n.localeName.split('_').first,
        );

    // 已有回应：key -> 我自己的回应事件（用于再次点击时撤回）
    final myReactionEvents = <String, Event>{};
    for (final reactionEvent
        in event.aggregatedEvents(timeline, RelationshipTypes.reaction)) {
      if (reactionEvent.senderId != myUserId) continue;
      final key = reactionEvent.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) myReactionEvents[key] = reactionEvent;
    }
    final canReact =
        event.status.isSent && controller.room.canSendDefaultMessages;

    void toggleReaction(String key) {
      final ownEvent = myReactionEvents[key];
      if (ownEvent != null) {
        unawaited(ownEvent.redactEvent());
      } else {
        unawaited(controller.room.sendReaction(event.eventId, key));
      }
    }

    final items = <_ActionItem>[
      if (canReply)
        _ActionItem(
          icon: Icons.reply_outlined,
          img: "assets/images/chat/menu/reply.png",
          label: l10n.reply,
          onTap: () => controller.replyTo(event),
        ),
      if (canCopy)
        _ActionItem(
          icon: Icons.copy_outlined,
          img: "assets/images/chat/menu/copy.png",
          label: l10n.copy,
          onTap: () => controller.copyEventsAction([event]),
        ),
      if (canTranslate)
        _ActionItem(
          icon: Icons.translate_outlined,
          img: "assets/images/chat/menu/translate.png",
          label: l10n.translate,
          onTap: () => controller.translateEventAction(event),
        ),
      if (canEdit)
        _ActionItem(
          icon: Icons.edit_outlined,
          img: "assets/images/chat/menu/edit.png",
          label: l10n.edit,
          onTap: () => controller.editEventAction(event),
        ),
      if (canPin)
        _ActionItem(
          icon: Icons.push_pin_outlined,
          img: "assets/images/chat/menu/pind.png",
          label: pinned ? l10n.unpin : l10n.pin,
          onTap: () => controller.pinEventAction(event),
        ),
      if (canForward)
        _ActionItem(
          icon: Icons.forward_outlined,
          img: "assets/images/chat/menu/forward.png",
          label: l10n.forward,
          onTap: () => controller.forwardEventsAction([event]),
        ),
      if (canEndPoll)
        _ActionItem(
          icon: Icons.stop_circle_outlined,
          label: l10n.endPoll,
          onTap: () => event.endPoll(),
        ),
      if (canDelete)
        _ActionItem(
          icon: Icons.delete_outline,
          img: "assets/images/chat/menu/del.png",
          label: l10n.delete,
          isDestructive: true,
          onTap: () => controller.redactEventsAction([event]),
        ),
    ];

    if (items.isEmpty && !canReact) return;

    await _showPopup(
      context: context,
      anchor: anchor,
      isMine: isMine,
      editedAt: editedAt,
      editedLabel: l10n.edited,
      todayLabel: l10n.today,
      yesterdayLabel: l10n.yesterday,
      selectLabel: l10n.select,
      items: items,
      onSelect: () => controller.enterSelectMode(event),
      reactionBar: canReact
          ? QuickReactionBar(
              myReactions: myReactionEvents.keys.toSet(),
              onReact: toggleReaction,
              onMore: () {
                showReactionEmojiPicker(
                  context,
                  onEmoji: (emoji) {
                    if (myReactionEvents.containsKey(emoji)) return;
                    unawaited(
                      controller.room.sendReaction(event.eventId, emoji),
                    );
                  },
                );
              },
            )
          : null,
    );
  }

  static Future<void> _showPopup({
    required BuildContext context,
    required Offset anchor,
    required bool isMine,
    required DateTime? editedAt,
    required String editedLabel,
    required String todayLabel,
    required String yesterdayLabel,
    required String selectLabel,
    required List<_ActionItem> items,
    required VoidCallback onSelect,
    QuickReactionBar? reactionBar,
  }) {
    final mediaQuery = MediaQuery.of(context);
    const menuWidth = 230.0;
    const horizontalMargin = 12.0;
    // 快捷表情栏（236）比菜单卡片（230）略宽，整体按宽的布局，
    // 同时不能超出屏幕
    final desiredWidth =
        reactionBar == null ? menuWidth : QuickReactionBar.barWidth;
    final popupWidth =
        desiredWidth.clamp(0.0, mediaQuery.size.width - horizontalMargin * 2);

    double left;
    if (isMine) {
      left = (anchor.dx - popupWidth - 8)
          .clamp(horizontalMargin, mediaQuery.size.width - popupWidth - horizontalMargin);
    } else {
      left = (anchor.dx + 8)
          .clamp(horizontalMargin, mediaQuery.size.width - popupWidth - horizontalMargin);
    }

    return showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      useSafeArea: false,
      builder: (dialogContext) {
        final safeTop = mediaQuery.padding.top + 8;
        final safeBottom = mediaQuery.padding.bottom + 8;
        return Padding(
          padding: EdgeInsets.only(top: safeTop, bottom: safeBottom),
          child: Stack(
            children: [
              _AnchoredMenu(
                anchor: anchor,
                left: left,
                popupWidth: popupWidth,
                width: menuWidth,
                editedAt: editedAt,
                editedLabel: editedLabel,
                todayLabel: todayLabel,
                yesterdayLabel: yesterdayLabel,
                selectLabel: selectLabel,
                items: items,
                onSelect: onSelect,
                reactionBar: reactionBar,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnchoredMenu extends StatelessWidget {
  final Offset anchor;
  final double left;

  /// 整个浮层（表情栏 + 菜单卡片）的宽度
  final double popupWidth;

  /// 菜单卡片自身宽度
  final double width;
  final DateTime? editedAt;
  final String editedLabel;
  final String todayLabel;
  final String yesterdayLabel;
  final String selectLabel;
  final List<_ActionItem> items;
  final VoidCallback onSelect;
  final QuickReactionBar? reactionBar;

  const _AnchoredMenu({
    required this.anchor,
    required this.left,
    required this.popupWidth,
    required this.width,
    required this.editedAt,
    required this.editedLabel,
    required this.todayLabel,
    required this.yesterdayLabel,
    required this.selectLabel,
    required this.items,
    required this.onSelect,
    this.reactionBar,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    const itemHeight = 50.0;
    final headerHeight = editedAt == null ? 0.0 : 54.0;
    const selectHeight = 58.0;
    final cardHeight = headerHeight + items.length * itemHeight + selectHeight;
    const barHeight = 52.0;
    const barGap = 8.0;
    final totalHeight =
        cardHeight + (reactionBar == null ? 0 : barHeight + barGap);

    // Stack 位于去掉安全区的 Padding 内，坐标需换算
    final stackTop = mq.padding.top + 8;
    final stackBottom = mq.padding.bottom + 8;
    final stackHeight = mq.size.height - stackTop - stackBottom;

    double? top;
    double? bottom;
    // 优先显示在手指上方，空间不够则放下方
    if (anchor.dy - stackTop - totalHeight - 12 > 0) {
      bottom = stackHeight - (anchor.dy - stackTop) + 12;
    } else {
      top = anchor.dy - stackTop + 12;
      // 下方空间也不够时贴底，避免菜单超出屏幕产生 overflow
      if (top + totalHeight > stackHeight) {
        top = (stackHeight - totalHeight).clamp(0.0, stackHeight);
      }
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          // 整个浮层（表情栏+卡片）按 popupWidth 布局，卡片自身固定 width 居中
          width: popupWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (reactionBar != null) ...[
                // 点击表情/更多后先关闭菜单，再执行回调
                QuickReactionBar(
                  myReactions: reactionBar!.myReactions,
                  onReact: (emoji) {
                    Navigator.of(context).pop();
                    reactionBar!.onReact(emoji);
                  },
                  onMore: () {
                    Navigator.of(context).pop();
                    reactionBar!.onMore();
                  },
                ),
                SizedBox(height: barGap),
              ],
              Flexible(
                child: SizedBox(
                  width: width > popupWidth ? popupWidth : width,
                  child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).cardBackground,
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 26,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (editedAt != null) ...[
                          SizedBox(
                            height: 54,
                            child: Padding(
                              padding:
                                  EdgeInsets.symmetric(horizontal: 18),
                              child: Row(
                                children: [
                                  Image.asset("assets/images/chat/menu/edited.png",width: 26,),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      '$editedLabel ${_formatEditedTime(editedAt!, todayLabel, yesterdayLabel)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        ],
                        ...items.map((item) => _itemView(context, item)),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _selectView(context),
                      ],
                    ),
                    ),
                  ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _itemView(BuildContext context, _ActionItem item) {
    final color = item.isDestructive ? Colors.red : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        item.onTap();
      },
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              item.img!=null?
              Image.asset(item.img!,width: 22,)
              :
              Icon(item.icon, size: 22, color: color),
              SizedBox(width: 14),
              Text(
                item.label,
                style: TextStyle(fontSize: 16, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectView(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onSelect();
      },
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Image.asset("assets/images/chat/menu/sel.png",width: 26,),
              SizedBox(width: 14),
              Text(
                selectLabel,
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatEditedTime(
    DateTime ts,
    String todayLabel,
    String yesterdayLabel,
  ) {
    final local = ts.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;
    if (isToday) return '$todayLabel $hh:$mm';
    if (isYesterday) return '$yesterdayLabel $hh:$mm';
    return '${local.month}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}

class _ActionItem {
  final IconData icon;
  final String? img;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionItem({
    required this.icon,
    this.img,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}
