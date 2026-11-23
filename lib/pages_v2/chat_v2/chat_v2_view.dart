import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/input_bar_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/message_bubble_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/ongoing_call_banner.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/pinned_messages_banner.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/remark.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

class ChatV2View extends StatelessWidget {
  final ChatV2Controller controller;

  const ChatV2View(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = FluffyThemes.isColumnMode(context);
    final room = controller.roomOrNull;
    if (room == null) {
      return Scaffold(
        backgroundColor: V2Theme.of(context).scaffoldBackground,
        body: Column(
          children: [
            V2AppBar(
              showBack: !isWide,
              onBack: () => context.go('/v2/rooms'),
            ),
            Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    // 自动加入邀请
    if (room.membership == Membership.invite) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (room.membership == Membership.invite) {
          await room.join();
        }
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: V2Theme.of(context).scaffoldBackground,
        body: Column(
          children: [
            controller.isSelecting
                ? _buildSelectAppBar(context)
                : _buildAppBar(context, room, isWide),
            // 群聊进行中的通话横幅（自己已加入时不显示）
            if (!controller.isSelecting)
              OngoingCallBanner(controller: controller),
            // 置顶消息横幅（有置顶消息时显示）
            if (!controller.isSelecting)
              PinnedMessagesBanner(controller: controller),
            Expanded(child: _buildMessageList(context)),
            // 多选模式或无发消息权限时隐藏输入栏
            if (!controller.isSelecting)
              room.canSendDefaultMessages
                  ? InputBarV2(controller: controller)
                  : SizedBox(height: 10,)// _buildNoPermissionHint(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectAppBar(BuildContext context) {
    final l10n = L10n.of(context);
    final selected = controller.selectedEvents;
    final canRedact = selected.every(controller.canRedactEvent);
    final hasText = selected.any(controller.isTextMessage);
    return ColoredBox(
      color: V2Theme.of(context).cardBackground,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.close, size: 24),
                color: V2Theme.of(context).accent,
                onPressed: controller.clearSelectedEvents,
              ),
              Expanded(
                child: Text(
                  selected.length.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  icon: Image.asset(
                    'assets/images/chat/menu/copy.png',
                    width: 26,
                    height: 26,
                  ),
                  color: V2Theme.of(context).textSecondary,
                  tooltip: l10n.copy,
                  onPressed: () =>
                      controller.copyEventsAction(selected.toList()),
                ),
              IconButton(
                icon: Image.asset(
                  'assets/images/chat/menu/forward.png',
                  width: 26,
                  height: 26,
                ),
                color: V2Theme.of(context).textSecondary,
                tooltip: l10n.forward,
                onPressed: () =>
                    controller.forwardEventsAction(selected.toList()),
              ),
              if (canRedact)
                IconButton(
                  icon: Image.asset(
                    'assets/images/chat/menu/del.png',
                    width: 26,
                    height: 26,
                  ),
                  color: Colors.red,
                  tooltip: l10n.delete,
                  onPressed: () =>
                      controller.redactEventsAction(selected.toList()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, Room room, bool isWide) {
    final l10n = L10n.of(context);
    final baseDisplayName = room.getLocalizedDisplayname(MatrixLocals(l10n));
    final remark = room.directChatMatrixID != null
        ? RemarkStore.getRemark(room.client, room.directChatMatrixID!)
        : null;
    final displayName = remark ?? baseDisplayName;
    final isMuted = room.pushRuleState != PushRuleState.notify;
    return V2AppBar(
      showBack: !isWide,
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (isMuted) ...[
            SizedBox(width: 6),
            Icon(
              Icons.notifications_off,
              size: 18,
              color: V2Theme.of(context).accent,
            ),
          ],
        ],
      ),
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          // 直接进入时栈中无上一页，兜底回主页
          context.go('/v2/rooms');
        }
      },
      // 私聊显示在线状态（PresenceBuilder 自行刷新）；群聊显示成员数
      subtitleWidget: room.isDirectChat
          ? PresenceBuilder(
              client: controller.sendingClient,
              userId: room.directChatMatrixID,
              builder: (context, presence) {
                final isOnline = presence?.presence.isOnline ?? false;
                return Text(
                  isOnline ? l10n.online : l10n.offline,
                  style: TextStyle(
                    fontSize: 12,
                    color: isOnline ? V2Theme.of(context).accent : V2Theme.of(context).textSecondary,
                  ),
                );
              },
            )
          : Text(
              l10n.membersCount(
                (room.summary.mJoinedMemberCount ?? 1) +
                    (room.summary.mInvitedMemberCount ?? 0),
              ),
              style: TextStyle(
                fontSize: 12,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
      action: V2CircleIconButton(
        icon: Icons.more_horiz,
        onTap: () async {
          final result = await context.push(
            '/v2/rooms/chat/${controller.roomId}/details',
          );
          // 返回后刷新：备注变化更新标题；清空记录则重载时间线
          if (result == 'historyCleared') {
            await controller.reloadTimeline();
          } else {
            controller.updateView();
          }
        },
      ),
    );
  }

  Widget _buildMessageList(BuildContext context) {
    final timeline = controller.timeline;
    if (timeline == null) {
      return Center(child: CircularProgressIndicator());
    }

    final visibleEvents = controller.visibleEvents;

    if (visibleEvents.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).noMessagesYet,
          style: TextStyle(color: V2Theme.of(context).textSecondary),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => controller.inputFocus.unfocus(),
      child: Stack(
        children: [
          ListView.custom(
            reverse: true,
            controller: controller.scrollController,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            childrenDelegate: SliverChildBuilderDelegate(
              (context, index) {
                // reverse 列表的最后一个 child 在视觉最顶部：历史加载入口
                if (index == visibleEvents.length) {
                  return _buildHistoryLoader(timeline);
                }
                final event = visibleEvents[index];
                // reverse 列表：index-1 是更新一条（视觉下方），
                // index+1 是更老一条（视觉上方）
                final nextEvent = index > 0 ? visibleEvents[index - 1] : null;
                final olderEvent = index < visibleEvents.length - 1
                    ? visibleEvents[index + 1]
                    : null;
                // 最老的一条（index 为最后一个，视觉最上方）始终保留日期
                final isFirst = olderEvent == null;

                return AutoScrollTag(
                  key: ValueKey(event.eventId),
                  controller: controller.scrollController,
                  index: index,
                  child: MessageBubbleV2(
                    event: event,
                    nextEvent: nextEvent,
                    olderEvent: olderEvent,
                    isFirst: isFirst,
                    timeline: timeline,
                    controller: controller,
                  ),
                );
              },
              childCount:
                  visibleEvents.length + (timeline.canRequestHistory ? 1 : 0),
              findChildIndexCallback: (key) {
                if (key is! ValueKey) return null;
                final eventId = key.value;
                final eventIndex = visibleEvents.indexWhere(
                  (e) => e.eventId == eventId,
                );
                return eventIndex >= 0 ? eventIndex : null;
              },
            ),
          ),
          // 向下滚动按钮
          if (controller.showScrollDownButton)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'scroll_down',
                onPressed: controller.scrollDown,
                backgroundColor: V2Theme.of(context).cardBackground,
                foregroundColor: V2Theme.of(context).accent,
                child: Icon(Icons.arrow_downward, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  /// 顶部历史加载项：被构建（进入预渲染区）即自动请求更早的消息，
  /// 实现连续上滑加载；首屏不足一屏时也会自动补到填满为止。
  Widget _buildHistoryLoader(Timeline timeline) {
    if (!timeline.canRequestHistory) return SizedBox(height: 24);

    // retention 截止：最老消息已过期，不再加载更早历史，也不显示加载器
    final maxLifetime = controller.retentionMaxLifetime;
    final oldest = controller.oldestMessageTs;
    if (maxLifetime != null &&
        oldest != null &&
        DateTime.now().difference(oldest).inMilliseconds >= maxLifetime) {
      return SizedBox(height: 24);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.requestHistory();
    });

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
