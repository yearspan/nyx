import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

/// V2 置顶消息列表页
///
/// 入口：私聊/群聊设置 → 置顶消息
/// 展示当前房间所有置顶消息，有权限时可逐条取消置顶。
class PinnedMessagesV2 extends StatefulWidget {
  final String roomId;

  const PinnedMessagesV2({super.key, required this.roomId});

  @override
  State<PinnedMessagesV2> createState() => _PinnedMessagesV2State();
}

class _PinnedMessagesV2State extends State<PinnedMessagesV2> {
  Room? get room =>
      Matrix.of(context).client.getRoomById(widget.roomId);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = this.room;

    if (room == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: Text(l10n.youAreNoLongerParticipatingInThisChat)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.pinnedMessages,
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/v2/rooms');
                }
              },
            ),
            Expanded(
              // 监听置顶状态变化，取消置顶后实时刷新
              child: StreamBuilder(
                stream: room.client.onRoomState.stream
                    .where((u) => u.roomId == room.id),
                builder: (context, _) {
                  final pinnedEventIds = room.pinnedEventIds;
                  if (pinnedEventIds.isEmpty) {
                    return _buildEmpty(l10n);
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: pinnedEventIds.length,
                    separatorBuilder: (_, _) => SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final eventId = pinnedEventIds[index];
                      return FutureBuilder<Event?>(
                        future: room.getEventById(eventId),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return SizedBox(
                              height: 88,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: V2Theme.of(context).accent,
                                ),
                              ),
                            );
                          }
                          return _PinnedMessageCard(
                            event: snapshot.data!,
                            onUnpin: () => _unpin(room, eventId),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(L10n l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.push_pin_outlined,
            size: 56,
            color: V2Theme.of(context).textSecondary,
          ),
          SizedBox(height: 12),
          Text(
            l10n.pinnedMessagesEmpty,
            style: TextStyle(
              fontSize: 15,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unpin(Room room, String eventId) async {
    final pinnedEventIds = room.pinnedEventIds
        .where((id) => id != eventId)
        .toList();
    try {
      await room.setPinnedEvents(pinnedEventIds);
    } catch (e) {
      debugPrint('[PinnedMessages] unpin failed: $e');
      if (mounted) {
        V2Toast.show(e.toString());
      }
    }
  }
}

/// 单条置顶消息卡片
class _PinnedMessageCard extends StatelessWidget {
  final Event event;
  final VoidCallback onUnpin;

  const _PinnedMessageCard({
    required this.event,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final sender = event.senderFromMemoryOrFallback;
    final canUnpin = event.room.canSendEvent(EventTypes.RoomPinnedEvents);
    final locale = safeDateFormatLocale(context);
    final time = DateFormat('yyyy/MM/dd HH:mm', locale).format(
      event.originServerTs,
    );
    final body = event.calcLocalizedBodyFallback(
      MatrixLocals(l10n),
      hideReply: true,
    ).replaceAll('\n', ' ').trim();

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(
                mxContent: sender.avatarUrl,
                name: sender.calcDisplayname(),
                size: 36,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sender.calcDisplayname(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (canUnpin)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onUnpin,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).accentLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin_outlined,
                          size: 14,
                          color: V2Theme.of(context).accent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          l10n.unpin,
                          style: TextStyle(
                            fontSize: 12,
                            color: V2Theme.of(context).accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            body,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
