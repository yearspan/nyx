import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/user_profile_v2.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/remark.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/qr_code_viewer.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_context_menu.dart';
import 'package:flutter_advanced_switch/flutter_advanced_switch.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets_v2/v2_toast.dart';

/// V2 私聊设置页面（仿微信风格）
///
/// 入口：聊天页右上角 more → /rooms/:roomId/details
/// 展示对方资料、快捷操作（静音/呼叫/视频）及会话设置项。
class ChatDetailsV2 extends StatefulWidget {
  final String roomId;

  const ChatDetailsV2({super.key, required this.roomId});

  @override
  State<ChatDetailsV2> createState() => _ChatDetailsV2State();
}

class _ChatDetailsV2State extends State<ChatDetailsV2> {
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);
  StreamSubscription<BasicEvent>? _accountDataSub;

  @override
  void initState() {
    super.initState();
    MatrixState.currentViewingRoomId = widget.roomId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = Matrix.of(context).client;
      // ignore: deprecated_member_use
      _accountDataSub = client.onAccountData.stream.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    if (MatrixState.currentViewingRoomId == widget.roomId) {
      MatrixState.currentViewingRoomId = null;
    }
    _accountDataSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = this.room;

    if (room == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(l10n.youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    // 监听房间状态变化（置顶/静音等操作后实时刷新）；备注由 account_data 订阅刷新
    return StreamBuilder(
      stream: room.client.onRoomState.stream.where((u) => u.roomId == room.id),
      builder: (context, _) {
        final directChatId = room.directChatMatrixID;
        final isDirectChat = directChatId != null;
        final baseDisplayName = room.getLocalizedDisplayname(
          MatrixLocals(l10n),
        );
        final remark = directChatId != null
            ? RemarkStore.getRemark(room.client, directChatId)
            : null;
        // 备注优先作为显示名（好友别名）
        final displayName = remark ?? baseDisplayName;
        final isMuted = room.pushRuleState != PushRuleState.notify;
        final isPinned = room.isFavourite;
        // 私聊：仅当对方 master key 已通过交互验证（verified）或首次信任（TOFU）时显示「已验证」
        final masterKey = directChatId != null
            ? room.client.userDeviceKeys[directChatId]?.masterKey
            : null;
        final isVerified =
            masterKey?.verified == true ||
            masterKey?.trustOnFirstUseSince != null;

        return Scaffold(
          backgroundColor: V2Theme.of(context).scaffoldBackground,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                V2AppBar(
                  action: isDirectChat
                      ? V2CircleIconButton(
                          icon: Icons.more_horiz,
                          onTap: () => _showMoreMenu(room, directChatId),
                        )
                      : null,
                  onBack: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/v2/rooms');
                    }
                  },
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    children: isDirectChat
                        ? _buildDirectChatBody(
                            room,
                            l10n,
                            displayName,
                            directChatId,
                            isMuted,
                            isPinned,
                            isVerified,
                            remark,
                          )
                        : _buildGroupChatBody(room, l10n, isMuted, isPinned),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 私聊设置页内容（原版布局）
  List<Widget> _buildDirectChatBody(
    Room room,
    L10n l10n,
    String displayName,
    String? directChatId,
    bool isMuted,
    bool isPinned,
    bool isVerified,
    String? remark,
  ) {
    return [
      // 头像 + 昵称 + ID
      Center(
        child: Column(
          children: [
            Avatar(mxContent: room.avatar, name: displayName, size: 88),
            SizedBox(height: 12),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (directChatId != null) ...[
              SizedBox(height: 4),
              Text(
                directChatId,
                style: TextStyle(
                  fontSize: 13,
                  color: V2Theme.of(context).textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      SizedBox(height: 24),

      // 快捷操作：静音 / 呼叫 / 视频
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: isMuted ? Icons.notifications_off : Icons.notifications_none,
            label: l10n.mute,
            color: isMuted ? V2Theme.of(context).accent : null,
            onTap: () => _toggleMute(room),
          ),
          _ActionButton(
            icon: Icons.call,
            img: "assets/images/setting/voice.png",
            label: l10n.call,
            onTap: () => _startCall(room, MatrixRtcCallIntent.voice),
          ),
          _ActionButton(
            icon: Icons.videocam,
            label: l10n.video,
            img: "assets/images/setting/video.png",
            onTap: () => _startCall(room, MatrixRtcCallIntent.video),
          ),
        ],
      ),
      SizedBox(height: 20),

      // 设置卡片
      _SettingsCard(
        children: [
          _SettingsTile.navigate(
            icon: Icons.notifications_none,
            img: "assets/images/setting/msg_notice.png",
            iconBg: Color(0xFFFFE9E2),
            iconColor: V2Theme.of(context).accent,
            title: l10n.messageNotify,
            onTap: () => context.push('/v2/notifications/room/${room.id}'),
          ),
          _SettingsTile.toggle(
            icon: Icons.star_border,
            img: "assets/images/setting/pin.png",
            iconBg: Color(0xFFFFE9E2),
            iconColor: V2Theme.of(context).accent,
            title: l10n.pin,
            value: isPinned,
            onChanged: (_) => _togglePin(room),
          ),
        ],
      ),
      SizedBox(height: 16),
      _SettingsCard(
        children: [
          _SettingsTile.navigate(
            icon: Icons.person_outline,
            img: "assets/images/setting/personal.png",
            iconBg: Color(0xFFFFE0EC),
            iconColor: Color(0xFFFF2D55),
            title: l10n.personalProfile,
            trailing: isVerified ? l10n.verified : null,
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/profile'),
          ),
          _SettingsTile.navigate(
            icon: Icons.edit_outlined,
            img: "assets/images/setting/remark.png",
            iconBg: Color(0xFFFFF3E0),
            iconColor: Color(0xFFFF9500),
            title: l10n.setRemark,
            trailing: remark,
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/remark'),
          ),
        ],
      ),
      SizedBox(height: 16),

      _SettingsCard(
        children: [
          _SettingsTile.navigate(
            icon: Icons.push_pin_outlined,
            img: "assets/images/setting/pin_msg.png",
            iconBg: Color(0xFFFFE9E2),
            iconColor: V2Theme.of(context).accent,
            title: l10n.pinnedMessages,
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/pinned'),
          ),
          // _SettingsTile.navigate(
          //   icon: Icons.description_outlined,
          //   img: 'assets/images/setting/protocel.png',
          //   iconBg: Color(0xFFFFE9E2),
          //   iconColor: V2Theme.of(context).accent,
          //   title: l10n.agreement,
          //   onTap: () {},
          // ),
          _SettingsTile.navigate(
            icon: Icons.folder_outlined,
            img: 'assets/images/setting/media_file.png',
            iconBg: Color(0xFFFFF3E0),
            iconColor: Color(0xFFFF9500),
            title: l10n.mediaAndFiles,
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/media'),
          ),
        ],
      ),
      SizedBox(height: 24),
    ];
  }

  /// 群设置页内容（仿截图布局）
  List<Widget> _buildGroupChatBody(
    Room room,
    L10n l10n,
    bool isMuted,
    bool isPinned,
  ) {
    final displayName = room.getLocalizedDisplayname(MatrixLocals(l10n));
    final memberCount =
        (room.summary.mJoinedMemberCount ?? 0) +
        (room.summary.mInvitedMemberCount ?? 0);
    // 自身在群中的角色（所有者 / 管理员 / 协管员 / 成员）
    final ownRole = room.ownPowerLevel.role;
    // 仅所有者可解散群聊；其余角色只能退出。
    // 兼容旧版本房间创建者权限为 100（admin）而非最高级的情况：
    // 房间创建者同样视为所有者。
    final isOwner =
        ownRole == PowerLevelRole.owner ||
        room.creatorUserIds.contains(room.client.userID ?? '');
    // 能否管理隐私与安全（加入规则 / 历史消息可见性）
    final canManagePrivacy =
        room.canChangeJoinRules || room.canChangeHistoryVisibility;
    // 能否管理角色与权限（修改 m.room.power_levels）
    final canManageRoles = room.canChangePowerLevel;
    // 能否编辑群资料（群名 / 头像 / 简介）
    final canEditRoom = room.canChangeStateEvent(EventTypes.RoomName);
    final topic = room.topic.trim();

    return [
      // 头像 + 群名 + 成员数 + 加密标识（管理员可点击进入编辑页）
      GestureDetector(
        onTap: canEditRoom
            ? () => context.push('/v2/rooms/chat/${room.id}/details/edit')
            : null,
        child: Center(
          child: Column(
            children: [
              Avatar(mxContent: room.avatar, name: displayName, size: 88),
              SizedBox(height: 12),
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 4),
              Text(
                l10n.membersCount(memberCount),
                style: TextStyle(
                  fontSize: 13,
                  color: V2Theme.of(context).textSecondary,
                ),
              ),
              if (room.encrypted) ...[
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? V2Theme.of(context).accent.withValues(alpha: 0.15)
                        : Color(0xFFFFE9E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock,
                        size: 12,
                        color: V2Theme.of(context).accent,
                      ),
                      SizedBox(width: 4),
                      Text(
                        l10n.encrypted,
                        style: TextStyle(
                          fontSize: 11,
                          color: V2Theme.of(context).accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      SizedBox(height: 24),

      // 快捷操作：呼叫 / 视频 / 取消静音 / 邀请 / 分享
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: isMuted ? Icons.notifications_off : Icons.notifications_none,
            label: isMuted ? l10n.unmuteChat : l10n.mute,
            color: isMuted ? V2Theme.of(context).accent : null,
            onTap: () => _toggleMute(room),
          ),
          _ActionButton(
            icon: Icons.call,
            img: "assets/images/setting/voice.png",
            label: l10n.call,
            onTap: () => _startCall(room, MatrixRtcCallIntent.voice),
          ),
          _ActionButton(
            icon: Icons.videocam,
            label: l10n.video,
            img: "assets/images/setting/video.png",
            onTap: () => _startCall(room, MatrixRtcCallIntent.video),
          ),

          _ActionButton(
            icon: Icons.person_add_alt,
            img: "assets/images/chat/add_member.png",
            label: l10n.invite,
            onTap: () => InviteMembersV2.show(context, roomId: room.id),
          ),
          if (PlatformInfos.isMobile)
            _ActionButton(
              icon: Icons.ios_share_outlined,
              //img:"assets/images/chat/share.png",
              label: l10n.share,
              onTap: () => _shareRoom(room),
            ),
        ],
      ),
      SizedBox(height: 20),

      // 简介（管理员可点击进入编辑页）
      _SettingsCard(
        children: [
          if (topic.isEmpty && canEditRoom)
            _SettingsTile.navigate(
              icon: Icons.edit_outlined,
              img: "assets/images/setting/remark.png",
              iconBg: Color(0xFFFFF3E0),
              iconColor: Color(0xFFFF9500),
              title: l10n.addBio,
              onTap: () => context.push('/v2/rooms/chat/${room.id}/details/edit'),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canEditRoom
                  ? () => context.push('/v2/rooms/chat/${room.id}/details/edit')
                  : null,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.bio,
                      style: TextStyle(
                        fontSize: 13,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      topic.isEmpty ? l10n.bioEmpty : topic,
                      style: TextStyle(
                        fontSize: 15,
                        color: topic.isEmpty
                            ? V2Theme.of(context).textSecondary
                            : Theme.of(context).colorScheme.onSurface,
                        fontStyle: topic.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      SizedBox(height: 16),

      _SettingsCard(
        children: [
          _SettingsTile.navigate(
            icon: Icons.notifications_none,
            img: "assets/images/setting/msg_notice.png",
            iconBg: Color(0xFFFFE9E2),
            iconColor: V2Theme.of(context).accent,
            title: l10n.messageNotify,
            onTap: () => context.push('/v2/notifications/room/${room.id}'),
          ),
          _SettingsTile.toggle(
            icon: Icons.star_border,
            img: "assets/images/setting/pin.png",
            iconBg: Color(0xFFFFE9E2),
            iconColor: V2Theme.of(context).accent,
            title: l10n.pin,
            value: isPinned,
            onChanged: (_) => _togglePin(room),
          ),
          if (canManagePrivacy)
            _SettingsTile.navigate(
              icon: Icons.people_outline,
              img: "assets/images/setting/private.png",
              iconBg: Color(0xFFE3F2FD),
              iconColor: Color(0xFF1976D2),
              title: l10n.privacyAndSecurity,
              onTap: () => context.push('/v2/rooms/chat/${room.id}/details/access'),
            ),
        ],
      ),

      SizedBox(height: 16),
      _SettingsCard(
        children: [
          _SettingsTile.navigate(
            icon: Icons.people_outline,
            img: "assets/images/setting/member.png",
            iconBg: Color(0xFFE3F2FD),
            iconColor: Color(0xFF1976D2),
            title: l10n.members,
            trailing: memberCount.toString(),
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/members'),
          ),
          if (canManageRoles)
            _SettingsTile.navigate(
              icon: Icons.people_outline,
              img: "assets/images/setting/role.png",
              iconBg: Color(0xFFE3F2FD),
              iconColor: Color(0xFF1976D2),
              title: l10n.rolesAndPermissions,
              onTap: () => context.push('/v2/rooms/chat/${room.id}/details/roles'),
            ),
        ],
      ),

      SizedBox(height: 16),

      // 设置项
      _SettingsCard(
        children: [
          _SettingsTile.navigate(
            icon: Icons.push_pin_outlined,
            img: "assets/images/setting/pin_msg.png",
            iconBg: Color(0xFFFFE9E2),
            iconColor: V2Theme.of(context).accent,
            title: l10n.pinnedMessages,
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/pinned'),
          ),
          _SettingsTile.navigate(
            icon: Icons.poll_outlined,
            img: "assets/images/setting/vote.png",
            iconBg: Color(0xFFF3E5F5),
            iconColor: Color(0xFF8E24AA),
            title: l10n.polls,
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/polls'),
          ),
          _SettingsTile.navigate(
            icon: Icons.folder_outlined,
            img: 'assets/images/setting/media_file.png',
            iconBg: Color(0xFFFFF3E0),
            iconColor: Color(0xFFFF9500),
            title: l10n.mediaAndFiles,
            onTap: () => context.push('/v2/rooms/chat/${room.id}/details/media'),
          ),
        ],
      ),
      SizedBox(height: 24),

      // 底部：退出社区 / 删除群聊
      _SettingsCard(
        children: [
          Container(
            decoration: BoxDecoration(
              color: V2Theme.of(context).cardBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                DangerTile(
                  icon: isOwner ? Icons.close : Icons.exit_to_app,
                  label: isOwner ? l10n.deleteGroupChat : l10n.leaveCommunity,
                  color: Color(0xFFFF3B30),
                  onTap: () => _leaveOrDeleteGroup(room, isOwner),
                ),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: 24),
    ];
  }

  /// 确保 Matrix 标识符带有服务器后缀（如 :nstalk.space）
  /// canonicalAlias 可能仅为本地别名，roomId 可能缺少服务器段，统一补全
  String _ensureServerSuffix(Room room, String identifier) {
    if (identifier.contains(':')) return identifier;
    final server = room.client.userID?.split(':').sublist(1).join(':');
    if (server == null || server.isEmpty) return identifier;
    return '$identifier:$server';
  }

  /// 群聊分享：跳转到群二维码页
  /// 使用 roomId（一定带服务器后缀）生成二维码，确保扫码加群时 via 路由可用
  Future<void> _shareRoom(Room room) async {
    showQrCodeViewer(context, room.id);
  }

  /// 退出群聊（管理员 / 协管员 / 成员）或解散群聊（仅所有者：踢出所有成员后离开）
  Future<void> _leaveOrDeleteGroup(Room room, bool canDelete) async {
    final l10n = L10n.of(context);
    final title = canDelete ? l10n.deleteGroupChat : l10n.leaveCommunity;
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: title,
      message: canDelete
          ? l10n.deleteGroupChatDescription
          : l10n.archiveRoomDescription,
    );
    if (confirmed != true || !mounted) return;

    try {
      if (canDelete) {
        // 仅所有者：踢出所有成员后再离开，达到「解散群聊」效果
        final participants = room.getParticipants();
        final ownId = room.client.userID;
        for (final user in participants) {
          if (user.id == ownId) continue;
          if (user.membership == Membership.join) {
            try {
              await room.kick(user.id);
            } catch (_) {}
          }
        }
      }
      await room.leave();
      if (!mounted) return;
      context.go('/v2/rooms');
    } catch (e) {
      debugPrint('[ChatDetails] leave/delete group failed: $e');
    }
  }

  /// 右上角 more 菜单
  Future<void> _showMoreMenu(Room room, String? directChatId) async {
    final l10n = L10n.of(context);
    final screenSize = MediaQuery.of(context).size;
    // 菜单位置贴近右上角（AppBar 高度 56 + 状态栏已被 SafeArea 处理）
    final position = Offset(screenSize.width - 16, 56);

    // 定义菜单项，用 label 区分点击的是哪一项
    const autoDeleteKey = 'autoDelete';
    const deleteAllKey = 'deleteAll';
    const clearHistoryKey = 'clearHistory';
    const qrKey = 'qr';
    const shareKey = 'share';
    const editKey = 'edit';

    final selected = await V2ContextMenu.show(
      context,
      position: position,
      items: [
        V2ContextMenuItem(
          id: autoDeleteKey,
          label: l10n.enableAutoDelete,
          icon: Icons.schedule_outlined,
        ),
        // V2ContextMenuItem(
        //   id: deleteAllKey,
        //   label: l10n.deleteAllMessages,
        //   icon: Icons.delete_outline,
        //   isDestructive: true,
        // ),
        V2ContextMenuItem(
          id: clearHistoryKey,
          label: l10n.clearChatHistory,
          icon: Icons.close,
          isDestructive: true,
        ),
        V2ContextMenuItem(
          id: qrKey,
          label: l10n.qrCode,
          icon: Icons.qr_code_rounded,
        ),
        // 分享到其它 App 仅移动端可用（share_plus），桌面/web 隐藏。
        if (PlatformInfos.isMobile)
          V2ContextMenuItem(
            id: shareKey,
            label: l10n.share,
            icon: Icons.ios_share,
          ),
        // V2ContextMenuItem(
        //   id: editKey,
        //   label: l10n.edit,
        //   icon: Icons.edit_outlined,
        // ),
      ],
    );
    if (selected == null || !mounted) return;

    switch (selected.id) {
      case autoDeleteKey:
        await _showAutoDeleteMenu(room, position);
        break;
      case deleteAllKey:
        await _deleteAllMessages(room, l10n);
        break;
      case clearHistoryKey:
        await _clearChatHistory(room, l10n);
        break;
      case qrKey:
        // 使用 roomId（带服务器后缀）确保扫码加群 via 路由可用
        final identifier = directChatId ?? room.id;
        showQrCodeViewer(context, identifier);
        break;
      case shareKey:
        final identifier = room.canonicalAlias.isNotEmpty
            ? room.canonicalAlias
            : directChatId ?? room.id;
        final link =
            'https://nstalk.space/#/${_ensureServerSuffix(room, identifier)}';
        await FluffyShare.share(link, context);
        break;
      case editKey:
        if (mounted) context.push('/v2/rooms/chat/${room.id}/details/remark');
        break;
    }
  }

  /// 自动删除子菜单
  Future<void> _showAutoDeleteMenu(Room room, Offset position) async {
    final l10n = L10n.of(context);
    const dayKey = 'day';
    const weekKey = 'week';
    const monthKey = 'month';
    const customKey = 'custom';
    const disableKey = 'disable';

    const day = Duration(days: 1);
    const week = Duration(days: 7);
    const month = Duration(days: 30);

    // 读取当前 m.room.retention 的 max_lifetime（毫秒）
    final retention = room.getState('m.room.retention')?.content;
    final maxLifetime = retention != null && retention['max_lifetime'] is int
        ? retention['max_lifetime'] as int
        : null;

    // 判断当前选中项，默认停用
    var checkedId = disableKey;
    if (maxLifetime != null) {
      if (maxLifetime == day.inMilliseconds) {
        checkedId = dayKey;
      } else if (maxLifetime == week.inMilliseconds) {
        checkedId = weekKey;
      } else if (maxLifetime == month.inMilliseconds) {
        checkedId = monthKey;
      } else {
        checkedId = customKey;
      }
    }

    final selected = await V2ContextMenu.show(
      context,
      position: position,
      items: [
        V2ContextMenuItem(
          id: dayKey,
          label: l10n.oneDay,
          icon: Icons.today,
          checked: checkedId == dayKey,
        ),
        V2ContextMenuItem(
          id: weekKey,
          label: l10n.oneWeek,
          icon: Icons.date_range,
          checked: checkedId == weekKey,
        ),
        V2ContextMenuItem(
          id: monthKey,
          label: l10n.oneMonth,
          icon: Icons.calendar_month,
          checked: checkedId == monthKey,
        ),
        V2ContextMenuItem(
          id: disableKey,
          label: l10n.disable,
          icon: Icons.block,
          isDestructive: true,
          checked: checkedId == disableKey,
        ),
      ],
    );
    if (selected == null || !mounted) return;

    switch (selected.id) {
      case dayKey:
        await _setRetention(room, day);
        break;
      case weekKey:
        await _setRetention(room, week);
        break;
      case monthKey:
        await _setRetention(room, month);
        break;
      case customKey:
        await _setCustomRetention(room, l10n);
        break;
      case disableKey:
        await _setRetention(room, null);
        break;
    }
  }

  /// 设置 / 清除 m.room.retention（max_lifetime，毫秒）
  Future<void> _setRetention(Room room, Duration? duration) async {
    try {
      final content = duration == null
          ? <String, Object?>{}
          : <String, Object?>{'max_lifetime': duration.inMilliseconds};
      await room.client.setRoomStateWithKey(
        room.id,
        'm.room.retention',
        '',
        content,
      );
      // 乐观更新本地状态，使 getState 立即生效（菜单一打开就能显示对勾）
      room.setState(
        StrippedStateEvent(
          type: 'm.room.retention',
          stateKey: '',
          content: content,
          senderId: room.client.userID ?? '',
        ),
      );
    } catch (e) {
      debugPrint('[ChatDetails] setRetention failed: $e');
    }
  }

  /// 自定义自动删除时长（天）
  Future<void> _setCustomRetention(Room room, L10n l10n) async {
    final controller = TextEditingController();
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(l10n.custom),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: l10n.oneDay),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    if (days == null || days <= 0 || !mounted) return;
    await _setRetention(room, Duration(days: days));
  }

  /// 删除所有消息（redact 时间线中所有消息事件）
  Future<void> _deleteAllMessages(Room room, L10n l10n) async {
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.deleteAllMessages,
      message: l10n.deleteAllMessagesConfirmation,
    );
    if (confirmed != true || !mounted) return;

    try {
      // 加载时间线并逐条 redact 消息事件
      final timeline = await room.getTimeline();
      for (final event in timeline.events) {
        if (event.type == EventTypes.Message) {
          try {
            await event.redactEvent();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[ChatDetails] deleteAllMessages failed: $e');
    }
  }

  /// 清空聊天记录：仅清除本地消息，保留会话，且置空 prev_batch 阻止回拉旧历史
  Future<void> _clearChatHistory(Room room, L10n l10n) async {
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.clearChatHistory,
      message: l10n.clearChatHistoryConfirmation,
    );
    if (confirmed != true || !mounted) return;
    try {
      final client = room.client;
      final db = client.database;

      // 1. 先拿到当前所有事件 ID（timeline 清空后就拿不到了）
      final eventIds = await db.getEventIdList(room, includeSending: true);

      // 2. 立即清除时间线片段 + 置空 prev_batch，界面立刻无消息且不再回拉旧历史
      await db.deleteTimelineForRoom(room.id);
      room.prev_batch = null;
      await db.setRoomPrevBatch(null, room.id, client);

      // 3. 后台逐条清理孤儿事件，不阻塞界面
      unawaited(Future.forEach(eventIds, (id) => db.removeEvent(id, room.id)));

      // 4. 返回聊天页并通知其刷新时间线
      if (mounted) context.pop('historyCleared');
    } catch (e) {
      debugPrint('[ChatDetails] clearChatHistory failed: $e');
    }
  }

  Future<void> _toggleMute(Room room) async {
    try {
      await room.setPushRuleState(
        room.pushRuleState == PushRuleState.notify
            ? PushRuleState.mentionsOnly
            : PushRuleState.notify,
      );
    } catch (e) {
      debugPrint('[ChatDetails] toggleMute failed: $e');
    }
  }

  Future<void> _togglePin(Room room) async {
    try {
      await room.setFavourite(!room.isFavourite);
    } catch (e) {
      debugPrint('[ChatDetails] togglePin failed: $e');
    }
  }

  /// 发起语音/视频通话
  Future<void> _startCall(Room room, MatrixRtcCallIntent intent) async {
    final matrix = Matrix.of(context);
    try {
      final granted = await room.ensureMatrixRtcCallPermission();
      if (!mounted) return;
      if (!granted) {
        V2Toast.show(L10n.of(context).callNotAllowed);
        return;
      }
      matrix.outgoingCallIntent = intent.name;
      matrix.callPosition.value = CallPosition.fullScreen;
      matrix.activeCallRoomId.value = room.id;
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[ChatDetails] startCall failed: $e');
    }
  }
}

/// 快捷操作按钮（静音 / 呼叫 / 视频）
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? img;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.img,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: V2Theme.of(context).cardBackground,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: img != null
                ? Image.asset(
                    img!,
                    width: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  )
                : Icon(icon, size: 24, color: iconColor),
          ),
          SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color ?? V2Theme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置卡片（圆角白底容器，内部为分隔的设置项）
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// 设置项：左侧彩色图标 + 标题 + 右侧（开关 / 副标题+箭头 / 仅箭头）
class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final String? img;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? trailing;
  final bool? toggleValue;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;

  const _SettingsTile.toggle({
    required this.icon,
    this.img,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) : trailing = null,
       toggleValue = value,
       onToggle = onChanged,
       onTap = null;

  const _SettingsTile.navigate({
    required this.icon,
    this.img,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.trailing,
    this.onTap,
  }) : toggleValue = null,
       onToggle = null;

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  ValueNotifier<bool>? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.toggleValue != null) {
      _controller = ValueNotifier<bool>(widget.toggleValue!);
    }
  }

  @override
  void didUpdateWidget(covariant _SettingsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toggleValue != null &&
        oldWidget.toggleValue != widget.toggleValue) {
      _controller ??= ValueNotifier<bool>(widget.toggleValue!);
      if (_controller!.value != widget.toggleValue) {
        _controller!.value = widget.toggleValue!;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIconBg = isDark
        ? widget.iconColor.withValues(alpha: 0.15)
        : widget.iconBg;
    return InkWell(
      onTap: widget.onTap,
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: V2Theme.of(context).divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            widget.img != null
                ? Image.asset(widget.img!, width: 30)
                : Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: effectiveIconBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.iconColor),
                  ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (widget.toggleValue != null)
              AdvancedSwitch(
                controller: _controller,
                activeColor: V2Theme.of(context).accent,
                inactiveColor: Theme.of(context).brightness == Brightness.dark
                    ? Color(0xFF3A3A3C)
                    : Color(0xFFE5E5E5),
                width: 50,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                ),
                onChanged: (value) => widget.onToggle?.call(value as bool),
              )
            else ...[
              if (widget.trailing != null)
                Text(
                  widget.trailing!,
                  style: TextStyle(
                    fontSize: 14,
                    color: V2Theme.of(context).textSecondary,
                  ),
                ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: V2Theme.of(context).textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
