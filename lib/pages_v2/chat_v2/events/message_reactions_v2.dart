import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 消息气泡下方的表情回应 chips（Telegram/微信风格）：
/// 圆角小胶囊展示 emoji + 回应人数，点击同一表情可撤回自己的回应。
class MessageReactionsV2 extends StatelessWidget {
  final Event event;
  final Timeline timeline;

  const MessageReactionsV2({
    super.key,
    required this.event,
    required this.timeline,
  });

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final myUserId = client.userID;

    // key -> 聚合信息
    final entries = <String, _ReactionAggregate>{};
    for (final reactionEvent
        in event.aggregatedEvents(timeline, RelationshipTypes.reaction)) {
      final key = reactionEvent.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == null) continue;
      final aggregate = entries.putIfAbsent(
        key,
        () => _ReactionAggregate(key: key),
      );
      aggregate.count++;
      if (reactionEvent.senderId == myUserId) {
        aggregate.myReactionEvent = reactionEvent;
      }
    }
    if (entries.isEmpty) return SizedBox.shrink();

    final list = entries.values.toList()
      ..sort((a, b) {
        // 我回应过的排前面，其余按人数
        if ((a.myReactionEvent != null) != (b.myReactionEvent != null)) {
          return a.myReactionEvent != null ? -1 : 1;
        }
        return b.count.compareTo(a.count);
      });

    final isMine = event.senderId == myUserId;
    final canSend = event.room.canSendDefaultMessages;

    return Padding(
      padding: EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
        children: [
          for (final entry in list)
            _ReactionChip(
              emoji: entry.key,
              count: entry.count,
              reacted: entry.myReactionEvent != null,
              onTap: !canSend
                  ? null
                  : () {
                      final myEvent = entry.myReactionEvent;
                      if (myEvent != null) {
                        unawaited(myEvent.redactEvent());
                      } else {
                        unawaited(event.room.sendReaction(event.eventId, entry.key));
                      }
                    },
            ),
        ],
      ),
    );
  }
}

class _ReactionAggregate {
  final String key;
  int count = 0;
  Event? myReactionEvent;

  _ReactionAggregate({required this.key});
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool reacted;
  final VoidCallback? onTap;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.reacted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 自己回应过：accent 淡底 + accent 边框；否则中性灰底
    final bg = reacted
        ? V2Theme.of(context).accent.withValues(alpha: 0.14)
        : Color(0xFFF0F0F2);
    final borderColor =
        reacted ? V2Theme.of(context).accent.withValues(alpha: 0.5) : Colors.transparent;
    final textColor = reacted ? V2Theme.of(context).accent : Color(0xFF666666);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 120),
        height: 26,
        padding: EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                emoji,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, height: 1.1),
              ),
            ),
            if (count > 1) ...[
              SizedBox(width: 3),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
