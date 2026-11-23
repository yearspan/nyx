import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/role_badge.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2 群角色成员列表页（管理员 / 协管员 共用）
///
/// 展示指定角色 [role] 的群成员列表，权限足够时可添加成员到该角色。
class RoomRoleMembersV2 extends StatefulWidget {
  final String roomId;
  final PowerLevelRole role;

  const RoomRoleMembersV2({
    super.key,
    required this.roomId,
    required this.role,
  });

  @override
  State<RoomRoleMembersV2> createState() => _RoomRoleMembersV2State();
}

class _RoomRoleMembersV2State extends State<RoomRoleMembersV2> {
  List<User>? _members;
  Object? _error;

  /// 编辑态：显示搜索框 + 每行删除图标
  bool _isEditing = false;

  /// 仅搜索态：显示搜索框，无删除图标
  bool _isSearching = false;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  Room get _room => Matrix.of(context).client.getRoomById(widget.roomId)!;

  /// 是否可修改权限（添加 / 移除管理员或协管员）
  bool get _canManageRoles => _room.canChangePowerLevel;

  /// 添加到该角色对应的权限等级
  int get _targetPowerLevel => switch (widget.role) {
        PowerLevelRole.admin => 100,
        PowerLevelRole.moderator => 50,
        _ => 0,
      };

  /// 是否处于搜索或编辑态（标题区显示搜索框）
  bool get _inSearchMode => _isEditing || _isSearching;

  /// 当前搜索过滤后的成员列表
  List<User> get _displayedMembers {
    final members = _members ?? const <User>[];
    if (_searchQuery.trim().isEmpty) return members;
    final q = _searchQuery.trim().toLowerCase();
    return members.where((u) {
      final name = u.calcDisplayname().toLowerCase();
      final id = u.id.toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  StreamSubscription? _updateSub;
  StreamSubscription? _roomStateSub;

  @override
  void initState() {
    super.initState();
    MatrixState.currentViewingRoomId = widget.roomId;
    _refresh();
    final client = Matrix.of(context).client;
    _updateSub = client.onSync.stream
        .where(
          (syncUpdate) {
            final joinRoom = syncUpdate.rooms?.join?[widget.roomId];
            if (joinRoom == null) return false;
            final stateEvents = joinRoom.state;
            if (stateEvents != null &&
                stateEvents.any(
                  (e) =>
                      e.type == EventTypes.RoomMember ||
                      e.type == EventTypes.RoomPowerLevels,
                )) {
              return true;
            }
            return joinRoom.timeline?.events?.any(
                  (e) => e.type == EventTypes.RoomMember,
                ) ??
                false;
          },
        )
        .listen((_) => _refresh());
    // 本地手动 setState（添加/移除角色）触发 onRoomState，单独监听以即时刷新
    _roomStateSub = client.onRoomState.stream
        .where(
          (e) =>
              e.roomId == widget.roomId &&
              (e.state.type == EventTypes.RoomMember ||
                  e.state.type == EventTypes.RoomPowerLevels),
        )
        .listen((_) => _refresh());
  }

  @override
  void dispose() {
    if (MatrixState.currentViewingRoomId == widget.roomId) {
      MatrixState.currentViewingRoomId = null;
    }
    _updateSub?.cancel();
    _roomStateSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      if (mounted) setState(() => _error = null);
      final participants = await _room.requestParticipants([Membership.join]);
      if (!mounted) return;
      final creators = _room.creatorUserIds;
      // 所有者不计入管理员 / 协管员列表
      final filtered = participants
          .where(
            (u) =>
                !creators.contains(u.id) &&
                u.powerLevel.role == widget.role,
          )
          .toList()
        ..sort((a, b) => b.powerLevel.level.compareTo(a.powerLevel.level));
      setState(() => _members = filtered);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// 弹出公共成员选择面板，将选中的成员设为管理员 / 协管员
  Future<void> _showAddSheet(L10n l10n) async {
    if (_members == null) return;
    // 禁用：所有者 + 已有任何角色（管理员/协管员）的成员。
    // 添加管理员或协管员时，只有普通成员可选，避免把已有角色的用户
    // 再设为另一个角色（升降级应通过编辑/移除流程处理）。
    final disabledIds = _room.getParticipants().where((u) {
      if (_room.creatorUserIds.contains(u.id)) return true;
      final role = u.powerLevel.role;
      return role == PowerLevelRole.admin || role == PowerLevelRole.moderator;
    }).map((u) => u.id).toSet();
    await InviteMembersV2.show(
      context,
      roomId: _room.id,
      mode: InviteMembersMode.selectMembers,
      title: widget.role == PowerLevelRole.admin
          ? l10n.addAdmin
          : l10n.addModerator,
      disabledUserIds: disabledIds,
      onConfirm: (userIds) async {
        for (final userId in userIds) {
          try {
            await _room.setPower(userId, _targetPowerLevel);
            // setPower 只发请求不更新本地状态，手动写入本地 power levels，
            // 使 getPowerLevelByUserId 立即返回新值，无需等待下一次 sync。
            final plState = _room.getState(EventTypes.RoomPowerLevels);
            if (plState != null) {
              final content = plState.content.copy();
              var users = content['users'];
              if (users is! Map<String, Object?>) {
                users = content['users'] = <String, Object?>{};
              }
              users[userId] = _targetPowerLevel;
              _room.setState(
                StrippedStateEvent(
                  type: EventTypes.RoomPowerLevels,
                  stateKey: '',
                  senderId: _room.client.userID!,
                  content: content,
                ),
              );
            }
          } catch (e) {
            if (context.mounted) V2Toast.show(e.toString());
          }
        }
        // if (context.mounted) {
        //   V2Toast.show(
        //     widget.role == PowerLevelRole.admin
        //         ? l10n.setAsAdminSuccess
        //         : l10n.setAsModeratorSuccess,
        //   );
        // }
      },
    );
    // 弹窗关闭后主动刷新列表（权限变更不一定能及时通过 sync 捕获）
    if (mounted) await _refresh();
  }

  /// 进入编辑态（搜索框 + 删除图标）
  void _enterEditMode() {
    setState(() {
      _isEditing = true;
      _isSearching = false;
    });
  }

  /// 退出搜索 / 编辑态
  void _exitSearchMode() {
    setState(() {
      _isEditing = false;
      _isSearching = false;
      _searchQuery = '';
    });
    _searchController.clear();
  }

  /// 取消某用户的管理员 / 协管员权限，降级为普通成员
  Future<void> _removeMember(User user, L10n l10n) async {
    final isAdmin = widget.role == PowerLevelRole.admin;
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.remove,
      message: isAdmin ? l10n.removeAdminConfirm : l10n.removeModeratorConfirm,
      confirmLabel: l10n.remove,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final plState = _room.getState(EventTypes.RoomPowerLevels);

      // 手动构造 power levels 内容，将目标用户降级为 0。
      // 注意：room version 12+ 中创建者自动拥有最高权限，且不允许
      // 出现在 content.users 中，需从 users 中移除创建者；
      // room version < 12 则保持创建者原有等级不变。
      final content = (plState?.content ?? <String, Object?>{}).copy();
      var users = content['users'];
      if (users is! Map<String, Object?>) {
        users = content['users'] = <String, Object?>{};
      }
      users[user.id] = 0;
      final me = _room.client.userID;
      final isV12Plus = (int.tryParse(_room.roomVersion ?? '') ?? 0) >= 12;
      if (me != null && _room.creatorUserIds.contains(me) && isV12Plus) {
        users.remove(me);
      }
      await _room.client.setRoomStateWithKey(
        _room.id,
        EventTypes.RoomPowerLevels,
        '',
        content,
      );
      // 手动更新本地 power levels
      _room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          senderId: me ?? '',
          content: content,
        ),
      );
      // if (context.mounted) {
      //   V2Toast.show(
      //     isAdmin ? l10n.removeAdminSuccess : l10n.removeModeratorSuccess,
      //   );
      // }
    } catch (e) {
      if (context.mounted) V2Toast.show(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final title =
        widget.role == PowerLevelRole.admin ? l10n.admin : l10n.moderator;
    final isAdmin = widget.role == PowerLevelRole.admin;
    final creators = _room.creatorUserIds;
    final displayed = _displayedMembers;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(
            title: _inSearchMode ? null : title,
            titleWidget: _inSearchMode ? _buildSearchField(l10n) : null,
            actions: _inSearchMode
                ? [
                    V2CircleIconButton(
                      icon: Icons.close,
                      onTap: _exitSearchMode,
                    ),
                  ]
                : [
                  GestureDetector(
                    onTap: _enterEditMode,
                    child:
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10,vertical: 6),
                        decoration: BoxDecoration(
                          color: V2Theme.of(context).cardBackground,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Image.asset("assets/images/common/search.png",width: 22, color: Theme.of(context).colorScheme.onSurface,),
                            SizedBox(width:6),
                            Text(
                              l10n.edit,
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      ),
                    )
                  ]
          ),
          Expanded(
            child: _error != null
                ? _buildError(l10n)
                : _members == null
                    ? Center(child: CircularProgressIndicator())
                    : displayed.isEmpty && _searchController.text.isNotEmpty
                        ? _buildEmptySearch(l10n)
                        : SingleChildScrollView(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 群聊管理员 / 群聊协管员 小标题
                                Text(
                                  isAdmin
                                      ? l10n.groupAdmins
                                      : l10n.groupModerators,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: V2Theme.of(context).textSecondary,
                                  ),
                                ),
                                SizedBox(height: 8),

                                if (_canManageRoles) ...[
                                  // 添加管理员 / 协管员 按钮
                                  InkWell(
                                    onTap: () => _showAddSheet(l10n),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: V2Theme.of(context).cardBackground,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: V2Theme.of(context).accentLight,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.person_add_alt_1,
                                              color: V2Theme.of(context).accent,
                                              size: 18,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            isAdmin
                                                ? l10n.addAdmin
                                                : l10n.addModerator,
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: V2Theme.of(context).accent,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                ],
                                // 成员列表
                                Container(
                                  decoration: BoxDecoration(
                                    color: V2Theme.of(context).cardBackground,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      for (var i = 0;
                                          i < displayed.length;
                                          i++) ...[
                                        _RoleMemberTile(
                                          user: displayed[i],
                                          isEditing: _isEditing,
                                          isOwner: creators
                                              .contains(displayed[i].id),
                                          role: widget.role,
                                          onRemove: () =>
                                              _removeMember(displayed[i], l10n),
                                        ),
                                        if (i < displayed.length - 1)
                                          Divider(
                                            height: 1,
                                            thickness: 0.5,
                                            color: V2Theme.of(context).divider,
                                            indent: 60,
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  isAdmin
                                      ? l10n.addAdminHelp
                                      : l10n.addModeratorHelp,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: V2Theme.of(context).textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  /// 标题区搜索框
  Widget _buildSearchField(L10n l10n) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      onChanged: (v) => setState(() => _searchQuery = v),
      style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface,),
      decoration: InputDecoration(
        hintText:  l10n.searchMembers,
        hintStyle: TextStyle(fontSize: 16, color: Color(0xFF8D8D93)),
        prefixIcon: Image.asset(
          "assets/images/common/search.png",
          width: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: V2Theme.of(context).divider,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  /// 搜索无结果空状态
  Widget _buildEmptySearch(L10n l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 56,
            color: V2Theme.of(context).textSecondary,
          ),
          SizedBox(height: 12),
          Text(
            l10n.noResults,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 4),
          Text(
            l10n.noResultsDescription,
            style: TextStyle(
              fontSize: 13,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(L10n l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: V2Theme.of(context).textSecondary,
          ),
          SizedBox(height: 12),
          TextButton.icon(
            onPressed: _refresh,
            icon: Icon(Icons.refresh_outlined),
            label: Text(l10n.tryAgain),
          ),
        ],
      ),
    );
  }
}

/// 角色成员列表项
class _RoleMemberTile extends StatelessWidget {
  final User user;
  final bool isEditing;
  final bool isOwner;
  final PowerLevelRole role;
  final VoidCallback? onRemove;

  const _RoleMemberTile({
    required this.user,
    required this.isEditing,
    required this.isOwner,
    required this.role,
    this.onRemove,
  });

  /// 右侧角色徽章（公共组件）
  Widget _roleBadge(BuildContext context) {
    return RoleBadge(role: role, isOwner: isOwner);
  }

  @override
  Widget build(BuildContext context) {
    final displayName = user.calcDisplayname();
    final canRemove = isEditing && !isOwner;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // 编辑态删除图标（所有者不可删除）
          if (isEditing) ...[
            SizedBox(
              width: 24,
              child: canRemove
                  ? GestureDetector(
                      onTap: onRemove,
                      child: Icon(
                        Icons.remove_circle,
                        color: Color(0xFFFF4D4F),
                        size: 22,
                      ),
                    )
                  : SizedBox.shrink(),
            ),
            SizedBox(width: 8),
          ],
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
          // 角色徽章
          _roleBadge(context),
        ],
      ),
    );
  }
}
