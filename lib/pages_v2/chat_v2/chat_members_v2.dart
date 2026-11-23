import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/role_badge.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 群聊成员列表页
///
/// 展示群成员，群主/管理员可添加成员、通过链接邀请。
class ChatMembersV2 extends StatefulWidget {
  final String roomId;

  const ChatMembersV2({super.key, required this.roomId});

  @override
  State<ChatMembersV2> createState() => _ChatMembersV2State();
}

class _ChatMembersV2State extends State<ChatMembersV2> {
  List<User>? _members;
  Object? _error;

  Room get _room => Matrix.of(context).client.getRoomById(widget.roomId)!;

  bool get _canInvite => _room.canInvite;

  StreamSubscription? _updateSub;

  @override
  void initState() {
    super.initState();
    MatrixState.currentViewingRoomId = widget.roomId;
    _refreshMembers();
    _updateSub = Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.rooms?.join?[widget.roomId]?.timeline?.events?.any(
                (state) => state.type == EventTypes.RoomMember,
              ) ??
              false,
        )
        .listen((_) => _refreshMembers());
  }

  @override
  void dispose() {
    if (MatrixState.currentViewingRoomId == widget.roomId) {
      MatrixState.currentViewingRoomId = null;
    }
    _updateSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshMembers() async {
    try {
      if (mounted) setState(() => _error = null);
      final participants = await _room.requestParticipants([Membership.join]);
      if (!mounted) return;
      participants.sort(
        (a, b) => b.powerLevel.level.compareTo(a.powerLevel.level),
      );
      setState(() => _members = participants);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _shareInviteLink() async {
    final alias = _room.canonicalAlias;
    if (alias.isNotEmpty) {
      await FluffyShare.share('https://nstalk.space/#/$alias', context);
    } else {
      await FluffyShare.share(
        'https://nstalk.space/#/${_room.id}',
        context,
      );
    }
    //if (mounted) V2Toast.show(l10n.shareInviteLink);
  }

  /// 点击成员弹出操作面板（所有成员均可查看）。
  ///
  /// 「移除成员」「封禁成员」仅在当前用户有权限时显示：
  /// 权限层级（高 → 低）所有者 > 管理员 > 协管员 > 成员，
  /// 由 [User.canKick] / [User.canBan] 内部校验
  /// `target.powerLevel < ownPowerLevel` 保证只能操作权限低于自己的成员。
  Future<void> _showMemberActions(User user) async {
    final l10n = L10n.of(context);
    final displayName = user.calcDisplayname();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: V2Theme.of(sheetContext).scaffoldBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖拽指示条
              Container(
                margin: EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: V2Theme.of(context).divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 成员信息
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Avatar(
                      mxContent: user.avatarUrl,
                      name: displayName,
                      size: 56,
                    ),
                    SizedBox(height: 10),
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      user.id,
                      style: TextStyle(
                        fontSize: 13,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 个人资料
              _SheetAction(
                icon: Icons.person_outline,
                label: l10n.personalProfile,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final client = Matrix.of(context).client;
                  final roomId = await client.startDirectChat(user.id);
                  if (!mounted) return;
                  context.push('/v2/rooms/chat/$roomId/details/profile');
                },
              ),
              // 移除成员（仅有权限时显示）
              if (user.canKick)
                _SheetAction(
                  icon: Icons.close,
                  iconColor: Colors.red,
                  label: l10n.removeMember,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await V2ConfirmDialog.show(
                      context,
                      title: l10n.areYouSure,
                      message: l10n.kickUserDescription,
                      confirmLabel: l10n.removeMember,
                    );
                    if (ok != true || !context.mounted) return;
                    try {
                      await user.kick();
                    } catch (e) {
                      if (context.mounted) V2Toast.show(e.toString());
                    }
                  },
                ),
              // 移除并封禁成员（仅有权限时显示）
              if (user.canBan)
                _SheetAction(
                  icon: Icons.block,
                  iconColor: Colors.red,
                  label: l10n.banMember,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await V2ConfirmDialog.show(
                      context,
                      title: l10n.areYouSure,
                      message: l10n.banUserDescription,
                      confirmLabel: l10n.banMember,
                    );
                    if (ok != true || !context.mounted) return;
                    try {
                      await user.ban();
                    } catch (e) {
                      if (context.mounted) V2Toast.show(e.toString());
                    }
                  },
                ),
              SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = _room;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.members,
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              // action: (_room.canKick || _room.canBan)
              //     ? TextButton(
              //         onPressed: () {
              //           // 编辑模式入口（暂未实现，后续可扩展成员管理）
              //         },
              //         child: Text(
              //           l10n.edit,
              //           style: TextStyle(
              //             fontSize: 16,
              //             color: V2Theme.of(context).accent,
              //             fontWeight: FontWeight.w600,
              //           ),
              //         ),
              //       )
              //     : null,
            ),
            Expanded(
              child: _error != null
                  ? _buildError(l10n)
                  : _members == null
                      ? Center(child: CircularProgressIndicator())
                      : _buildContent(l10n, room),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(L10n l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: V2Theme.of(context).textSecondary),
          SizedBox(height: 12),
          TextButton.icon(
            onPressed: _refreshMembers,
            icon: Icon(Icons.refresh_outlined),
            label: Text(l10n.tryAgain),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(L10n l10n, Room room) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 16),
          // 添加成员 / 通过链接邀请
          if (_canInvite)
            Container(
              decoration: BoxDecoration(
                color: V2Theme.of(context).cardBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _ActionTile(
                    icon: Icons.person_add_alt_1,
                    img: "assets/images/chat/add_member.png",
                    label: l10n.addMembers,
                    onTap: () => InviteMembersV2.show(context, roomId: room.id),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: V2Theme.of(context).divider,
                    indent: 16,
                    endIndent: 16,
                  ),
                  if (PlatformInfos.isMobile)
                    _ActionTile(
                      icon: Icons.link,
                      img: "assets/images/chat/link_invite.png",
                      label: l10n.inviteViaLink,
                      onTap: _shareInviteLink,
                    ),
                ],
              ),
            ),
          // 仅管理员可见提示
          // if (_room.canKick || _room.canBan) ...[
          //   SizedBox(height: 12),
          //   Padding(
          //     padding: EdgeInsets.symmetric(horizontal: 4),
          //     child: Text(
          //       l10n.memberListAdminOnlyNotice,
          //       style: TextStyle(
          //         fontSize: 12,
          //         color: V2Theme.of(context).textSecondary,
          //       ),
          //     ),
          //   ),
          // ],
          SizedBox(height: 20),
          // 联系人分区标题
          Text(
            l10n.contactsInThisChat,
            style: TextStyle(
              fontSize: 13,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
          SizedBox(height: 8),
          // 成员列表
          Container(
            decoration: BoxDecoration(
              color: V2Theme.of(context).cardBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _members!.length; i++) ...[
                  _MemberTile(
                    user: _members![i],
                    onTap: () => _showMemberActions(_members![i]),
                  ),
                  if (i < _members!.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: V2Theme.of(context).divider,
                      indent: 60,
                      endIndent: 16,
                    ),
                ],
              ],
            ),
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 操作项（添加成员 / 通过链接邀请）
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String? img;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    this.img,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            img!=null?
            Image.asset(img!,width: 24,)
            :
            Icon(icon, size: 22, color: V2Theme.of(context).accent),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 成员列表项
class _MemberTile extends StatelessWidget {
  final User user;
  final VoidCallback? onTap;

  const _MemberTile({required this.user, this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayName = user.calcDisplayname();
    // 房间创建者视为「所有者」（兼容旧版本房间创建者权限为 100 而非最高级的情况）
    final isCreator = user.room.creatorUserIds.contains(user.id);
    final displayRole = user.powerLevel.role;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Avatar(
              mxContent: user.avatarUrl,
              name: displayName,
              size: 40,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (displayRole != PowerLevelRole.user)
                        Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: RoleBadge(role: displayRole, isOwner: isCreator),
                        ),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(
                    user.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部操作面板的操作项
class _SheetAction extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor ?? V2Theme.of(context).accent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: iconColor ?? Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: V2Theme.of(context).textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
