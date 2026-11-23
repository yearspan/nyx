import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_list_v2/chat_list_v2.dart';
import 'package:fluffychat/pages_v2/chat_list_v2/last_event_preview.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/remark.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/search/v2_search_results.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_context_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

import '../../widgets_v2/v2_app_bar.dart';
import '../../widgets_v2/v2_search_bar.dart';

/// V2 聊天列表视图（View）
class ChatListV2View extends StatelessWidget {
  final ChatListV2Controller controller;
  const ChatListV2View(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = controller.filteredRooms;
    final invites = rooms
        .where((r) => r.membership == Membership.invite)
        .toList();
    final normalRooms = rooms
        .where((r) => r.membership != Membership.invite)
        .toList();
    final l10n = L10n.of(context);

    // 搜索模式：显示搜索结果页
    if (controller.isSearchMode) {
      return Column(
        children: [
          V2AppBar(
            title: l10n.search,
            showBack: true,
            onBack: controller.cancelSearch,
          ),
          // 搜索框
          V2SearchBar(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            hintText: l10n.search,
            onChanged: controller.onSearchEnter,
            onSubmitted: () => controller.onSearchEnter(
              controller.searchController.text,
            ),
          ),
          Expanded(child: _SearchResults(controller: controller)),
        ],
      );
    }

    return Column(
      children: [
        V2AppBar(
          title: l10n.chats,
          action: _ChatListAddButton(controller: controller),
          showBack: false,
        ),

        // 搜索框：点击进入搜索模式
        GestureDetector(
          onTap: controller.startSearch,
          child: AbsorbPointer(
            child: V2SearchBar(
              controller: controller.searchController,
              focusNode: controller.searchFocusNode,
              hintText: l10n.search,
            ),
          ),
        ),
        // 筛选标签
        // Padding(
        //   padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        //   child: Row(
        //     children: [
        //       // 左侧 X 按钮（清除筛选，显示全部聊天）
        //       GestureDetector(
        //         onTap: () => controller.switchFilter(-1),
        //         child: Container(
        //           padding: EdgeInsets.all(8),
        //           decoration: BoxDecoration(
        //             color: V2Theme.of(context).accentLight,
        //             shape: BoxShape.circle,
        //           ),
        //           child: Icon(
        //             Icons.close,
        //             color: V2Theme.of(context).accent,
        //             size: 18,
        //           ),
        //         ),
        //       ),
        //       SizedBox(width: 8),
        //       Expanded(
        //         child: Wrap(
        //           spacing: 8,
        //           children: [
        //             _FilterChip(
        //               label: l10n.users,
        //               selected: controller.selectedFilter == 0,
        //               onTap: () => controller.switchFilter(0),
        //             ),
        //             _FilterChip(
        //               label: l10n.unread,
        //               selected: controller.selectedFilter == 1,
        //               onTap: () => controller.switchFilter(1),
        //             ),
        //             _FilterChip(
        //               label: l10n.groupChats,
        //               selected: controller.selectedFilter == 2,
        //               onTap: () => controller.switchFilter(2),
        //             ),
        //             _FilterChip(
        //               label: l10n.pin,
        //               selected: controller.selectedFilter == 3,
        //               onTap: () => controller.switchFilter(3),
        //             ),
        //           ],
        //         ),
        //       ),
        //     ],
        //   ),
        // ),

        // 会话列表
        Expanded(
          child: (normalRooms.isEmpty && invites.isEmpty)
              ? _EmptyState(filter: controller.selectedFilter)
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 80),
                  itemCount: normalRooms.length + invites.length,
                  itemBuilder: (context, index) {
                    if (index < invites.length) {
                      final invite = invites[index];
                      return _InviteTile(
                        room: invite,
                        onAccept: () => controller.acceptInvite(invite),
                        onReject: () async {
                          final groupName = invite.getLocalizedDisplayname();
                          final confirmed = await V2ConfirmDialog.show(
                            context,
                            title: l10n.declineInviteTitle,
                            message: l10n.declineInviteConfirm(groupName),
                            confirmLabel: l10n.decline,
                            cancelLabel: l10n.cancel,
                          );
                          if (confirmed == true) {
                            await controller.rejectInvite(invite);
                          }
                        },
                      );
                    }
                    final room = normalRooms[index - invites.length];
                    return _ChatTile(
                      room: room,
                      onTap: () => controller.onChatTap(room),
                      controller: controller,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 搜索结果列表（复用公共组件 V2SearchResults）
class _SearchResults extends StatelessWidget {
  final ChatListV2Controller controller;
  const _SearchResults({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final keyword = controller.searchController.text.trim().toLowerCase();

    // 本地已加入房间按名称过滤
    final localRooms = client.rooms
        .where(
          (r) =>
              !r.isSpace &&
              r.membership != Membership.leave &&
              r.membership != Membership.ban &&
              (keyword.isEmpty ||
                  r.getLocalizedDisplayname().toLowerCase().contains(keyword)),
        )
        .toList();

    return V2SearchResults(
      roomSearchResult: controller.roomSearchResult,
      userSearchResult: controller.userSearchResult,
      isSearching: controller.isSearching,
      keyword: keyword,
      localRooms: localRooms,
      localSectionTitle: L10n.of(context).chats,
      onLocalRoomTap: controller.onChatTap,
      localRoomSubtitle: (room) => formatLastEventPreview(room, l10n),
    );
  }
}

/// 筛选标签（药丸形）
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? V2Theme.of(context).accent : V2Theme.of(context).cardBackground,
          borderRadius: BorderRadius.circular(18),
          border: selected ? null : Border.all(color: V2Theme.of(context).divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : V2Theme.of(context).textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 会话列表项
class _ChatTile extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  final ChatListV2Controller controller;

  const _ChatTile({
    required this.room,
    required this.onTap,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // 房间无名称时先加载 hero 用户，否则 getLocalizedDisplayname 会
    // 返回 "Empty chat" 而不是成员名称（与 v1 chat_list_item 行为一致）
    return FutureBuilder(
      future: room.name.isEmpty ? room.loadHeroUsers() : null,
      builder: (context, _) => _buildTile(context, l10n),
    );
  }

  Widget _buildTile(BuildContext context, L10n l10n) {
    final baseDisplayName = room.getLocalizedDisplayname();
    final directChatId = room.directChatMatrixID;
    final remark = directChatId != null
        ? RemarkStore.getRemark(room.client, directChatId)
        : null;
    final displayName = remark ?? baseDisplayName;
    final lastEvent = room.lastEvent;
    final lastMessage = formatLastEventPreview(room, l10n);
    final timeText = lastEvent != null
        ? _formatTime(lastEvent.originServerTs, context)
        : '';
    final isUnread = room.notificationCount > 0 || room.markedUnread;
    final isPinned = room.isFavourite;
    final isMuted = room.pushRuleState != PushRuleState.notify;

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) =>
          _showRoomContextMenu(context, details.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Avatar(mxContent: room.avatar, name: displayName, size: 48),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isPinned) ...[
                              SizedBox(width: 4),
                              Icon(
                                Icons.push_pin,
                                size: 14,
                                color: V2Theme.of(context).accent,
                              ),
                            ],
                            if (isMuted) ...[
                              SizedBox(width: 4),
                              Icon(
                                Icons.notifications_off,
                                size: 14,
                                color: V2Theme.of(context).accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        timeText,
                        style: TextStyle(
                          fontSize: 12,
                          color: V2Theme.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(
                            fontSize: 13,
                            color: isUnread
                                ? Colors.black
                                : V2Theme.of(context).textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isUnread)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: V2Theme.of(context).accent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            room.notificationCount > 99
                                ? '99+'
                                : room.notificationCount > 0
                                    ? '${room.notificationCount}'
                                    : '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      // if (!isUnread && room.lastEvent != null)
                      //   Icon(
                      //     room.isDirectChat &&
                      //             room.lastEvent?.senderId ==
                      //                 Matrix.of(context).client.userID
                      //         ? Icons.done_all
                      //         : Icons.done,
                      //     size: 16,
                      //     color: V2Theme.of(context).textSecondary,
                      //   ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 长按会话项弹出操作菜单
  Future<void> _showRoomContextMenu(
    BuildContext context,
    Offset position,
  ) async {
    final l10n = L10n.of(context);
    final isPinned = room.isFavourite;
    final isMuted = room.pushRuleState != PushRuleState.notify;
    final isUnread = room.markedUnread || room.notificationCount > 0;

    final selected = await V2ContextMenu.show(
      context,
      position: position,
      items: [
        V2ContextMenuItem(
          label: isUnread ? l10n.markAsRead : l10n.markAsUnread,
          icon: isUnread ? Icons.mark_email_read : Icons.mark_as_unread,
          img: isUnread ? "assets/images/chat/unread_sel.png": "assets/images/chat/unread.png"
        ),
        V2ContextMenuItem(
          label: isPinned ? l10n.unpin : l10n.pin,
          icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            img: isPinned ? "assets/images/chat/pin_sel.png": "assets/images/chat/pin.png"
        ),
        V2ContextMenuItem(
          label: isMuted ? l10n.unmuteChat : l10n.muteChat,
          icon: isMuted
              ? Icons.notifications_off
              : Icons.notifications_off_outlined,
            img: isMuted ? "assets/images/chat/mute_sel.png": "assets/images/chat/mute.png"
        ),
        V2ContextMenuItem(
          label: l10n.delete,
          icon: Icons.delete_outline,
          img: "assets/images/chat/del.png",
          isDestructive: true,
        ),
      ],
    );
    if (selected == null || !context.mounted) return;
    final label = selected.label;

    // 像微信一样直接操作，不弹加载框（本地状态立即更新，服务端同步在后台完成）
    try {
      if (label == l10n.markAsRead || label == l10n.markAsUnread) {
        await room.markUnread(!room.markedUnread);
      } else if (label == l10n.pin || label == l10n.unpin) {
        await room.setFavourite(!room.isFavourite);
      } else if (label == l10n.muteChat || label == l10n.unmuteChat) {
        await room.setPushRuleState(
          room.pushRuleState == PushRuleState.notify
              ? PushRuleState.mentionsOnly
              : PushRuleState.notify,
        );
      } else if (label == l10n.delete) {
        final confirmed = await V2ConfirmDialog.show(
          context,
          title: l10n.areYouSure,
          message: l10n.deleteChatDescription,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
        );
        if (confirmed != true || !context.mounted) return;
        // 仅从会话列表移除，不退出房间；收到新消息时会自动恢复显示
        await controller.hideRoom(room);
      }
    } catch (e) {
      Logs().w('[ChatList] context menu action failed: $e');
    }
  }

  String _formatTime(DateTime ts, BuildContext context) {
    final l10n = L10n.of(context);
    final locale = safeDateFormatLocale(context);
    final date = ts;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) {
      return DateFormat('HH:mm', locale).format(date);
    } else if (diff == 1) {
      return l10n.yesterday;
    } else if (diff < 7) {
      return DateFormat('E', locale).format(date);
    }
    return DateFormat('yy/MM/dd', locale).format(date);
  }
}

/// 群邀请卡片
class _InviteTile extends StatefulWidget {
  final Room room;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;

  const _InviteTile({
    required this.room,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends State<_InviteTile> {
  bool _accepting = false;
  bool _rejecting = false;

  Future<void> _handleAccept() async {
    if (_accepting || _rejecting) return;
    setState(() => _accepting = true);
    try {
      await widget.onAccept();
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _handleReject() async {
    if (_accepting || _rejecting) return;
    setState(() => _rejecting = true);
    try {
      await widget.onReject();
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayName = widget.room.getLocalizedDisplayname();
    final inviter =
        widget.room
            .getState(EventTypes.RoomMember, Matrix.of(context).client.userID!)
            ?.senderId ??
        '';
    final busy = _accepting || _rejecting;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
        border: Border.all(color: V2Theme.of(context).divider),
      ),
      child: Row(
        children: [
          Avatar(mxContent: widget.room.avatar, name: displayName, size: 40),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(
                  l10n.invitedYouToJoinGroup(inviter),
                  style: TextStyle(
                    fontSize: 12,
                    color: V2Theme.of(context).textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 拒绝按钮
          TextButton(
            onPressed: busy ? null : _handleReject,
            child: _rejecting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  )
                : Text(
                    l10n.reject,
                    style: TextStyle(color: V2Theme.of(context).textSecondary),
                  ),
          ),
          SizedBox(width: 4),
          // 接受按钮
          ElevatedButton(
            onPressed: busy ? null : _handleAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: V2Theme.of(context).accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: _accepting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.accept),
          ),
        ],
      ),
    );
  }
}

/// 空状态提示
class _EmptyState extends StatelessWidget {
  final int filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // 根据筛选类型选不同文案和图标
    late final String title;
    late final String desc;
    late final IconData icon;

    switch (filter) {
      case 0: // 用户
        title = l10n.emptyUsersTitle;
        desc = l10n.emptyUsersDesc;
        icon = Icons.person_outline;
        break;
      case 1: // 未读
        title = l10n.emptyUnreadTitle;
        desc = l10n.emptyUnreadDesc;
        icon = Icons.mark_email_read_outlined;
        break;
      case 2: // 群聊
        title = l10n.emptyGroupChatsTitle;
        desc = l10n.emptyGroupChatsDesc;
        icon = Icons.group_outlined;
        break;
      case 3: // 置顶
        title = l10n.emptyPinnedTitle;
        desc = l10n.emptyPinnedDesc;
        icon = Icons.push_pin_outlined;
        break;
      default: // 全部
        title = l10n.emptyChatsTitle;
        desc = l10n.emptyChatsDesc;
        icon = Icons.chat_bubble_outline;
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 80, left: 40, right: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                icon,
                size: 56,
                color: V2Theme.of(context).accent,
              ),
            ),
            SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              desc,
              style: TextStyle(
                fontSize: 13,
                color: V2Theme.of(context).textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 会话列表右上角 + 号按钮：点击后在按钮下方弹出菜单
/// （仿照聊天输入栏 + 号的 LayerLink + Overlay 实现）
class _ChatListAddButton extends StatefulWidget {
  final ChatListV2Controller controller;

  const _ChatListAddButton({required this.controller});

  @override
  State<_ChatListAddButton> createState() => _ChatListAddButtonState();
}

class _ChatListAddButtonState extends State<_ChatListAddButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;

  void _toggle() {
    if (_overlay != null) {
      _hide();
    } else {
      _show();
    }
  }

  void _hide() {
    _overlay?.remove();
    _overlay = null;
  }

  void _show() {
    final l10n = L10n.of(context);
    final controller = widget.controller;

    Widget row(IconData icon, String label, VoidCallback onTap) {
      return InkWell(
        onTap: () {
          _hide();
          onTap();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 26, color: Theme.of(context).colorScheme.onSurface),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final menu = Material(
      color: V2Theme.of(context).cardBackground,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(Icons.group_add_outlined, l10n.newGroupChat, controller.openNewGroup),
            row(Icons.person_add_outlined, l10n.inviteFriends, controller.shareInvite),
            row(Icons.add_link_outlined, l10n.joinRoom, controller.joinByAddress),
          ],
        ),
      ),
    );

    final overlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hide,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: Offset(0, 8),
            child: menu,
          ),
        ],
      ),
    );

    _overlay = overlay;
    Overlay.of(context, rootOverlay: true).insert(overlay);
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: V2CircleIconButton(
        icon: Icons.add,
        onTap: _toggle,
      ),
    );
  }
}
