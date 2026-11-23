import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:fluffychat/widgets/qr_code_viewer.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 个人资料页（仿微信风格）
///
/// 入口：私聊设置 → 个人资料（传 roomId）；
/// 搜索用户 → 个人资料（传 userId，无 DM 房间时也可查看）。
/// 联系人行根据是否存在 DM 自动切换「删除联系人 / 添加联系人」。
class UserProfileV2 extends StatefulWidget {
  final String? roomId;
  final String? userId;

  const UserProfileV2({super.key, this.roomId, this.userId});

  @override
  State<UserProfileV2> createState() => _UserProfileV2State();
}

class _UserProfileV2State extends State<UserProfileV2> {
  Client get client => Matrix.of(context).client;

  Room? get room =>
      widget.roomId != null ? client.getRoomById(widget.roomId!) : null;

  /// 优先从 DM 房间取对方 userId，否则用外部传入的 userId
  String? get userId => room?.directChatMatrixID ?? widget.userId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = this.room;
    final userId = this.userId;

    if (userId == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: Text(l10n.youAreNoLongerParticipatingInThisChat)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        // 联系人 / 屏蔽状态随 account data 变化实时刷新
        child: StreamBuilder<SyncUpdate>(
          stream: client.onSync.stream,
          builder: (context, _) {
            final isContact = client.getDirectChatFromUserId(userId) != null;
            final isBlocked = client.ignoredUsers.contains(userId);
            // 已完成交互验证 或 已通过 TOFU 信任对方，均视为"已验证"，不再显示验证入口
            final masterKey = client.userDeviceKeys[userId]?.masterKey;
            final isVerified =
                masterKey?.verified == true ;
                    //|| masterKey?.trustOnFirstUseSince != null;

            return ListView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _buildTopBar(userId),
                SizedBox(height: 12),
                _buildProfileHeader(room, userId),
                SizedBox(height: 20),
                _buildActionButtons(room, userId, isContact, l10n),
                SizedBox(height: 20),
                _buildBioCard(userId, l10n),
                // 仅联系人且未验证时显示验证入口，已验证则隐藏
                if (isContact && !isVerified) ...[
                  SizedBox(height: 20),
                  _buildVerifyCard(userId, l10n),
                ],
                SizedBox(height: 20),
                _buildDangerCard(
                  room: room,
                  userId: userId,
                  isContact: isContact,
                  isBlocked: isBlocked,
                  l10n: l10n,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 顶部：返回 + 二维码
  Widget _buildTopBar(String userId) {
    return Padding(
      padding: EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          V2CircleIconButton(
            icon: Icons.arrow_back_ios_new,
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/v2/rooms');
              }
            },
          ),
          V2CircleIconButton(
            icon: Icons.qr_code_scanner,
            onTap: () => showQrCodeViewer(context, userId),
          ),
        ],
      ),
    );
  }

  /// 头像 + 昵称 + @id + 已验证
  Widget _buildProfileHeader(Room? room, String userId) {
    return FutureBuilder<Profile>(
      future: client.getProfileFromUserId(userId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = profile?.displayName ??
            room?.getLocalizedDisplayname() ??
            userId.localpart ??
            userId;
        final isVerified =
            client.userDeviceKeys[userId]?.masterKey?.verified == true;

        return Column(
          children: [
            Avatar(
              mxContent: profile?.avatarUrl,
              name: displayName,
              size: 88,
            ),
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
              '@${userId.localpart}',
              style: TextStyle(
                fontSize: 13,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
            if (isVerified) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: V2Theme.of(context).accentLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified,
                      size: 14,
                      color: V2Theme.of(context).accent,
                    ),
                    SizedBox(width: 4),
                    Text(
                      L10n.of(context).verified,
                      style: TextStyle(
                        fontSize: 12,
                        color: V2Theme.of(context).accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 消息 / 呼叫 / 分享
  Widget _buildActionButtons(
    Room? room,
    String userId,
    bool isContact,
    L10n l10n,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          //img: "assets/images/setting/msg.png",
          label: l10n.messages,
          onTap: () => _openChat(room, userId),
        ),
        _ActionButton(
          icon: Icons.call,
          img: "assets/images/setting/voice.png",
          label: l10n.call,
          onTap: () => _startCall(room, userId, isContact),
        ),
        if (PlatformInfos.isMobile)
          _ActionButton(
            icon: Icons.ios_share_outlined,
            label: l10n.share,
            onTap: () => FluffyShare.share(
              'https://nstalk.space/#/$userId',
              context,
            ),
          ),
      ],
    );
  }

  /// 简介卡片
  Widget _buildBioCard(String userId, L10n l10n) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: PresenceBuilder(
        userId: userId,
        client: client,
        builder: (context, presence) {
          final bio = presence?.statusMsg;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.bio,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF666666),
                ),
              ),
              SizedBox(height: 8),
              Text(
                (bio == null || bio.isEmpty) ? l10n.bioEmpty : bio,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 验证用户卡片（仅联系人且未验证时显示）
  Widget _buildVerifyCard(String userId, L10n l10n) {
    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _verifyUser(userId),
        child: Container(
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? V2Theme.of(context).accent.withValues(alpha: 0.15)
                      : Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: Color(0xFF1677FF),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.verifyUser,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
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

  /// 发起用户验证：进入 V2 验证页，由页面在点击「开始验证」时创建请求
  void _verifyUser(String userId) {
    final roomId = widget.roomId;
    if (roomId == null) return;
    context.push('/v2/rooms/chat/$roomId/details/verify');
  }

  /// 删除/添加联系人 + 屏蔽用户
  Widget _buildDangerCard({
    required Room? room,
    required String userId,
    required bool isContact,
    required bool isBlocked,
    required L10n l10n,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          DangerTile(
            icon: isContact ? Icons.close : Icons.person_add_alt,
            label: isContact ? l10n.deleteContact : l10n.addContact,
            color: isContact? Color(0xFFFF3B30) : V2Theme.of(context).accent,
            onTap: () => isContact
                ? _deleteContact(room, l10n)
                : _addContact(userId),
          ),
          Divider(height: 0.5, color: V2Theme.of(context).divider),
          DangerTile(
            icon: isBlocked ? Icons.block_flipped : Icons.block,
            label: isBlocked ? l10n.unblockUser : l10n.blockUser,
            color: isContact? Color(0xFFFF3B30) : V2Theme.of(context).accent,
            onTap: () => isBlocked
                ? _unblockUser(room, userId, l10n)
                : _blockUser(room, userId, l10n),
          ),
        ],
      ),
    );
  }

  Future<void> _openChat(Room? room, String userId) async {
    final dmRoomId = client.getDirectChatFromUserId(userId) ??
        room?.id ??
        await client.startDirectChat(userId);
    if (!mounted) return;
    context.push('/v2/rooms/chat/$dmRoomId');
  }

  Future<void> _addContact(String userId) async {
    try {
      await client.startDirectChat(userId);
    } catch (e) {
      debugPrint('[UserProfile] addContact failed: $e');
      _showError(e);
    }
  }

  Future<void> _deleteContact(Room? room, L10n l10n) async {
    if (room == null) return;
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.deleteContact,
      message: l10n.areYouSure,
      confirmLabel: l10n.ok,
      cancelLabel: l10n.cancel,
    );
    if (confirmed != true) return;
    try {
      // leave() 会同时把房间从 m.direct 移除；房间已不存在，直接回主页
      await room.leave();
      if (mounted) context.go('/v2/rooms');
    } catch (e) {
      debugPrint('[UserProfile] deleteContact failed: $e');
      _showError(e);
    }
  }

  Future<void> _startCall(
    Room? room,
    String userId,
    bool isContact,
  ) async {
    try {
      final dmRoomId =
          client.getDirectChatFromUserId(userId) ??
              await client.startDirectChat(userId);
      final dmRoom = client.getRoomById(dmRoomId);
      if (dmRoom == null) return;
      final granted = await dmRoom.ensureMatrixRtcCallPermission();
      if (!granted || !mounted) return;
      final matrix = Matrix.of(context);
      matrix.outgoingCallIntent = MatrixRtcCallIntent.voice.name;
      matrix.callPosition.value = CallPosition.fullScreen;
      matrix.activeCallRoomId.value = dmRoom.id;
    } catch (e) {
      debugPrint('[UserProfile] startCall failed: $e');
      _showError(e);
    }
  }

  Future<void> _blockUser(Room? room, String userId, L10n l10n) async {
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.blockUser,
      message: l10n.areYouSure,
      confirmLabel: l10n.ok,
      cancelLabel: l10n.cancel,
    );
    if (confirmed != true) return;
    try {
      // 1. 直接写入 m.ignored_user_list，避免 SDK ignoreUser 的 clearCache()
      //    （会清空所有本地房间，看起来像"删除了聊天"）
      await _setIgnored(userId, ignored: true);
      // 2. 尝试通过房间权限等级禁止对方发消息：
      //    把 events_default 提到自己的权限等级，服务端会拒绝对方发送，
      //    对方客户端会收到发送失败提示。无权限修改时静默跳过。
      if (room != null) {
        try {
          await _setRoomMute(room, muted: true);
        } catch (e) {
          debugPrint('[UserProfile] setRoomMute failed (non-fatal): $e');
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] blockUser failed: $e');
      _showError(e);
    }
  }

  Future<void> _unblockUser(Room? room, String userId, L10n l10n) async {
    try {
      await _setIgnored(userId, ignored: false);
      // 恢复房间发消息权限（events_default 重置为默认 0）
      if (room != null) {
        try {
          await _setRoomMute(room, muted: false);
        } catch (e) {
          debugPrint('[UserProfile] restoreRoomMute failed (non-fatal): $e');
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] unblockUser failed: $e');
      _showError(e);
    }
  }

  /// 直接修改 m.ignored_user_list account data，不清空本地缓存
  Future<void> _setIgnored(String userId, {required bool ignored}) async {
    final list = client.ignoredUsers;
    if (ignored) {
      if (!list.contains(userId)) list.add(userId);
    } else {
      list.remove(userId);
    }
    await client.setAccountData(client.userID!, 'm.ignored_user_list', {
      'ignored_users': Map.fromEntries(list.map((k) => MapEntry(k, {}))),
    });
  }

  /// 通过 m.room.power_levels 控制本房间是否允许对方发消息。
  /// muted=true  时把 events_default 提到自己的权限等级，仅自己可发；
  /// muted=false 时把 events_default 恢复为 0，恢复正常。
  Future<void> _setRoomMute(Room room, {required bool muted}) async {
    if (!room.canChangeStateEvent(EventTypes.RoomPowerLevels)) return;
    final content = Map<String, Object?>.from(
      room.getState(EventTypes.RoomPowerLevels)?.content ??
          <String, Object?>{},
    );
    final myLevel = room.ownPowerLevel.level;
    content['events_default'] = muted ? myLevel : 0;
    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.RoomPowerLevels,
      '',
      content,
    );
  }

  void _showError(Object e) {
    if (!mounted) return;
    V2Toast.show(e.toString());
  }
}

/// 快捷操作按钮（与私聊设置页保持一致：圆形白底阴影）
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? img;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.img,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            child: img!=null?
                Image.asset(img!,width: 26,color: Theme.of(context).colorScheme.onSurface,)
                :
            Icon(icon, size: 24, color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部红色操作行
class DangerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const DangerTile({
    required this.icon,
    required this.label,
    required this.onTap, this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = color ?? Color(0xFFFF3B30);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDark
                    ? effectiveColor.withValues(alpha: 0.15)
                    : (color == null ? Color(0xFFFFEBEB) : color!.withOpacity(.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: effectiveColor),
            ),
            SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
