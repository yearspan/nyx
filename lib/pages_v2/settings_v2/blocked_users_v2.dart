import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2「已屏蔽」用户列表页
///
/// 入口：个人设置 → 隐私与安全 → 已屏蔽用户。
/// - 顶部「屏蔽用户」按钮：弹出联系人 / 用户目录选择面板
/// - 下方卡片列出所有已屏蔽用户
/// - 右上角「编辑」：进入编辑态，每行左侧出现红色减号，点击取消屏蔽
class BlockedUsersV2 extends StatefulWidget {
  const BlockedUsersV2({super.key});

  @override
  State<BlockedUsersV2> createState() => _BlockedUsersV2State();
}

class _BlockedUsersV2State extends State<BlockedUsersV2> {
  Client get client => Matrix.of(context).client;

  bool _editing = false;

  StreamSubscription<BasicEvent>? _accountDataSub;

  List<String> get _blockedIds => client.ignoredUsers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: deprecated_member_use
      _accountDataSub = client.onAccountData.stream.listen((event) {
        if (event.type == 'm.ignored_user_list' && mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _accountDataSub?.cancel();
    super.dispose();
  }

  /// 同步解析已屏蔽用户的展示信息（头像 / 昵称）。
  /// 优先从私聊房间的已缓存成员中取，取不到则回退到 ID 本地部分。
  ({String name, Uri? avatarUrl}) _displayOf(String userId) {
    for (final room in client.rooms) {
      if (room.isDirectChat && room.directChatMatrixID == userId) {
        final user = room.unsafeGetUserFromMemoryOrFallback(userId);
        return (name: user.calcDisplayname(), avatarUrl: user.avatarUrl);
      }
    }
    return (name: userId.localpart ?? userId, avatarUrl: null);
  }

  /// 直接修改 m.ignored_user_list，将用户移出屏蔽名单
  Future<void> _unblock(String userId) async {
    try {
      final list = client.ignoredUsers.toList()..remove(userId);
      await client.setAccountData(client.userID!, 'm.ignored_user_list', {
        'ignored_users': {for (final k in list) k: <String, Object?>{}},
      });
      if (mounted && _blockedIds.isEmpty) setState(() => _editing = false);
    } catch (e) {
      if (mounted) V2Toast.show(e.toString());
    }
  }

  /// 弹出公共成员选择面板（InviteMembersV2 invite 模式），
  /// 将选中的用户加入屏蔽名单。
  ///
  /// - 数据源：联系人（私聊对方）+ 用户目录搜索
  /// - 已屏蔽用户 / 自己 自动禁用（不可选）
  /// - 确认后通过 m.ignored_user_list 写入屏蔽名单
  Future<void> _openBlockSheet() async {
    final l10n = L10n.of(context);
    final blocked = client.ignoredUsers.toSet();
    if (client.userID != null) blocked.add(client.userID!);
    // invite 模式需要一个 roomId 作上下文，取任意已加入房间即可；
    // 这里 disabledUserIds 已显式指定，房间成员不会再被额外禁用。
    final roomId = client.rooms.firstOrNull?.id ?? '';
    await InviteMembersV2.show(
      context,
      roomId: roomId,
      mode: InviteMembersMode.invite,
      title: l10n.blockUsers,
      disabledUserIds: blocked,
      onConfirm: (userIds) async {
        if (userIds.isEmpty) return;
        final list = client.ignoredUsers.toList();
        for (final id in userIds) {
          if (!list.contains(id)) list.add(id);
        }
        await client.setAccountData(client.userID!, 'm.ignored_user_list', {
          'ignored_users': {for (final k in list) k: <String, Object?>{}},
        });
      },
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final ids = _blockedIds;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(
            title: l10n.blocked,
            actions: ids.isEmpty
                ? null
                : [
                    GestureDetector(
                      onTap: () => setState(() => _editing = !_editing),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
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
                        child: Text(
                          _editing ? l10n.done : l10n.edit,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 屏蔽用户 按钮
                  InkWell(
                    onTap: _openBlockSheet,
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
                              Icons.back_hand_outlined,
                              color: V2Theme.of(context).accent,
                              size: 18,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            l10n.blockUsers,
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
                  if (ids.isNotEmpty) ...[
                    SizedBox(height: 12),
                    // 已屏蔽用户列表卡片
                    Container(
                      decoration: BoxDecoration(
                        color: V2Theme.of(context).cardBackground,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < ids.length; i++) ...[
                            _BlockedUserTile(
                              userId: ids[i],
                              display: _displayOf(ids[i]),
                              isEditing: _editing,
                              onUnblock: () => _unblock(ids[i]),
                            ),
                            if (i < ids.length - 1)
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
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 已屏蔽用户列表项
class _BlockedUserTile extends StatelessWidget {
  final String userId;
  final ({String name, Uri? avatarUrl}) display;
  final bool isEditing;
  final VoidCallback onUnblock;

  const _BlockedUserTile({
    required this.userId,
    required this.display,
    required this.isEditing,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (isEditing) ...[
            GestureDetector(
              onTap: onUnblock,
              child: Icon(
                Icons.remove_circle,
                color: Color(0xFFFF4D4F),
                size: 22,
              ),
            ),
            SizedBox(width: 8),
          ],
          Avatar(mxContent: display.avatarUrl, name: display.name, size: 40),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  userId,
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
    );
  }
}
