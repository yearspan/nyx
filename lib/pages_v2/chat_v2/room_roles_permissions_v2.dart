import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 角色与权限页面
///
/// 入口：群设置 → 角色与权限
/// 提供「管理员」「协管员」「更改我的角色」「权限」四个入口。
class RoomRolesPermissionsV2 extends StatefulWidget {
  final String roomId;

  const RoomRolesPermissionsV2({super.key, required this.roomId});

  @override
  State<RoomRolesPermissionsV2> createState() => _RoomRolesPermissionsV2State();
}

class _RoomRolesPermissionsV2State extends State<RoomRolesPermissionsV2> {
  List<User>? _members;

  Room get _room => Matrix.of(context).client.getRoomById(widget.roomId)!;

  /// 当前用户在群内的角色
  PowerLevelRole get _ownRole => _room.ownPowerLevel.role;

  /// 是否为所有者（含旧版本房间创建者权限为 admin 的兼容情况）
  bool get _isOwner =>
      _ownRole == PowerLevelRole.owner ||
      _room.creatorUserIds.contains(_room.client.userID ?? '');

  /// 管理员入口仅所有者可见
  bool get _canSeeAdminEntry => _isOwner;

  /// 协管员入口对所有者和管理员可见，协管员自己不可见
  bool get _canSeeModeratorEntry =>
      _isOwner || _ownRole == PowerLevelRole.admin;

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
            // 成员变更或权限等级变更都需要刷新计数
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
    // 本地手动 setState（如添加管理员后更新本地 power levels）触发 onRoomState，
    // 不会走 onSync，单独监听以保证计数实时刷新。
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
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final participants = await _room.requestParticipants([Membership.join]);
      if (!mounted) return;
      setState(() => _members = participants);
    } catch (_) {
      // 忽略错误，计数时回退为 0
      if (mounted) setState(() => _members = const []);
    }
  }

  /// 统计指定角色的成员数量（所有者不计入任何角色）
  int _countByRole(PowerLevelRole role) {
    final members = _members;
    if (members == null) return 0;
    final creators = _room.creatorUserIds;
    return members
        .where((u) => !creators.contains(u.id) && u.powerLevel.role == role)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final adminCount = _countByRole(PowerLevelRole.admin);
    final moderatorCount = _countByRole(PowerLevelRole.moderator);

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.rolesAndPermissions),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // 角色入口卡片
                  _Card(
                    children: [
                      if (_canSeeAdminEntry) ...[
                        _EntryTile(
                          icon: Icons.shield_outlined,
                          img: "assets/images/common/role_admin.png",
                          iconBg: Color(0xFFE8F5E9),
                          iconColor: Color(0xFF2E7D32),
                          title: l10n.admin,
                          trailing: adminCount.toString(),
                          onTap: () => context.push(
                            '/v2/rooms/chat/${widget.roomId}/details/roles/admin',
                          ),
                        ),
                      ],
                      if (_canSeeModeratorEntry) ...[
                        if (_canSeeAdminEntry) const _Divider(),
                        _EntryTile(
                          icon: Icons.shield_outlined,
                          img: "assets/images/common/role_moderator.png",
                          iconBg: Color(0xFFFFF3E0),
                          iconColor: Color(0xFFE65100),
                          title: l10n.moderator,
                          trailing: moderatorCount.toString(),
                          onTap: () => context.push(
                            '/v2/rooms/chat/${widget.roomId}/details/roles/moderator',
                          ),
                        ),
                      ],
                      if (_canSeeAdminEntry || _canSeeModeratorEntry)
                        const _Divider(),
                      // 所有者不能更改自己的角色
                      if (!_isOwner)
                        _EntryTile(
                          icon: Icons.person_outline,
                          img: "assets/images/common/role_my.png",
                          iconBg: Color(0xFFE3F2FD),
                          iconColor: Color(0xFF1976D2),
                          title: l10n.changeMyRole,
                          onTap: () => _changeMyRole(l10n),
                        ),
                    ],
                  ),
                  SizedBox(height: 16),
                  // 权限入口卡片
                  _Card(
                    children: [
                      _EntryTile(
                        icon: Icons.key_outlined,
                        img: "assets/images/common/permission.png",
                        iconBg: Color(0xFFECEFF1),
                        iconColor: Color(0xFF546E7A),
                        title: l10n.permissions,
                        onTap: () => context.push(
                          '/v2/rooms/chat/${widget.roomId}/details/permissions',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 更改我的角色：从底部弹出降级选项
  Future<void> _changeMyRole(L10n l10n) async {
    final me = _room.client.userID;
    if (me == null) return;
    final currentRole = _isOwner ? PowerLevelRole.owner : _ownRole;

    // 可选的降级目标（低于当前角色）
    final options = <({String label, String icon, int level})>[
      if (currentRole == PowerLevelRole.owner)
        (label: l10n.demoteToAdmin, icon: "assets/images/common/role_admin.png", level: 100),
      if (currentRole == PowerLevelRole.owner ||
          currentRole == PowerLevelRole.admin)
        (label: l10n.demoteToModerator, icon: "assets/images/common/role_moderator.png", level: 50),
      if (currentRole != PowerLevelRole.user)
        (label: l10n.demoteToMember, icon: "assets/images/common/role_my.png", level: 0),
    ];
    if (options.isEmpty) return;

    final targetLevel = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChangeMyRoleSheet(options: options),
    );
    if (targetLevel == null || !mounted) return;

    try {
      await _room.setPower(me, targetLevel);
      // 手动更新本地 power levels，使 ownPowerLevel 立即刷新
      final plState = _room.getState(EventTypes.RoomPowerLevels);
      if (plState != null) {
        final content = plState.content.copy();
        var users = content['users'];
        if (users is! Map<String, Object?>) {
          users = content['users'] = <String, Object?>{};
        }
        users[me] = targetLevel;
        _room.setState(
          StrippedStateEvent(
            type: EventTypes.RoomPowerLevels,
            stateKey: '',
            senderId: me,
            content: content,
          ),
        );
      }
      if (mounted) setState(() {});
      // 降级为协管员或成员后，已无管理员/协管员管理权限，返回群聊设置页
      if (targetLevel <= 50 && mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        V2Toast.show(e.toString());
      }
    }
  }
}

/// 「更改我的角色」底部弹窗
class _ChangeMyRoleSheet extends StatelessWidget {
  final List<({String label, String icon, int level})> options;

  const _ChangeMyRoleSheet({required this.options});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部拖动指示条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: V2Theme.of(context).divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                l10n.changeMyRole,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Text(
                l10n.changeMyRoleConfirmMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: V2Theme.of(context).textSecondary,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: V2Theme.of(context).cardBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      InkWell(
                        onTap: () => Navigator.pop(context, options[i].level),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Image.asset(options[i].icon,width: 24,),
                              SizedBox(width: 12),
                              Text(
                                options[i].label,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFFF6B35),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i < options.length - 1)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 48,
                          color: V2Theme.of(context).divider,
                        ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: V2Theme.of(context).accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    l10n.cancel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆角白色卡片容器
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

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

/// 入口列表项
class _EntryTile extends StatelessWidget {
  final IconData icon;
  final String? img;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  const _EntryTile({
    required this.icon,
    this.img,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.trailing,
    this.onTap,
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
                Image.asset(img!,width: 34,)
                :
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
            if (trailing != null) ...[
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 14,
                  color: V2Theme.of(context).textSecondary,
                ),
              ),
              SizedBox(width: 4),
            ],
            Icon(
              Icons.chevron_right,
              size: 20,
              color: V2Theme.of(context).textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: V2Theme.of(context).divider,
      indent: 60,
    );
  }
}
