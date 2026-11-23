import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/user_profile_v2.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 搜索结果列表（微信风格：分组 + 竖向列表项）
///
/// 会话列表、联系人等页面复用。本地房间来源和点击行为由外部传入。
class V2SearchResults extends StatelessWidget {
  /// 服务端公开房间目录结果
  final QueryPublicRoomsResponse? roomSearchResult;

  /// 服务端用户目录结果
  final SearchUserDirectoryResponse? userSearchResult;

  /// 是否正在请求服务端
  final bool isSearching;

  /// 搜索关键词（用于本地房间过滤）
  final String keyword;

  /// 本地房间（已按关键词过滤好）
  final List<Room> localRooms;

  /// 本地房间分组标题
  final String localSectionTitle;

  /// 本地房间点击回调
  final void Function(Room room) onLocalRoomTap;

  /// 本地房间副标题（如最后消息预览）。为空时用默认在线状态/成员数。
  final String Function(Room room)? localRoomSubtitle;

  const V2SearchResults({
    super.key,
    required this.roomSearchResult,
    required this.userSearchResult,
    required this.isSearching,
    required this.keyword,
    required this.localRooms,
    required this.localSectionTitle,
    required this.onLocalRoomTap,
    this.localRoomSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // 关键词为空时停留在搜索页，结果区留空
    if (keyword.isEmpty) {
      return SizedBox.shrink();
    }

    final publicRooms = roomSearchResult?.chunk
            .where((c) => c.roomType != 'm.space')
            .toList() ??
        <PublishedRoomsChunk>[];

    final users = userSearchResult?.results ?? <Profile>[];

    // 加载中
    if (isSearching &&
        localRooms.isEmpty &&
        publicRooms.isEmpty &&
        users.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: CircularProgressIndicator(color: V2Theme.of(context).accent),
        ),
      );
    }

    // 无结果
    if (localRooms.isEmpty && publicRooms.isEmpty && users.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 80, left: 40, right: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/common/empty.png', width: 100),
              SizedBox(height: 16),
              Text(
                l10n.noResultsDescription,
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

    return ListView(
      padding: EdgeInsets.only(bottom: 80),
      children: [
        // 公开聊天室
        if (publicRooms.isNotEmpty) ...[
          _SearchSectionHeader(title: l10n.publicRooms),
          ...publicRooms.map(
            (chunk) => _PublicRoomResultTile(
              chunk: chunk,
              onTap: () => _onPublicRoomTap(context, chunk),
            ),
          ),
        ],
        // 用户
        if (users.isNotEmpty) ...[
          _SearchSectionHeader(title: l10n.users),
          ...users.map(
            (profile) => _UserResultTile(
              profile: profile,
              onTap: () => _onUserTap(context, profile),
            ),
          ),
        ],
        // 本地房间
        if (localRooms.isNotEmpty) ...[
          _SearchSectionHeader(title: localSectionTitle),
          ...localRooms.map(
            (room) => _LocalRoomResultTile(
              room: room,
              onTap: () => onLocalRoomTap(room),
              subtitle: localRoomSubtitle?.call(room),
            ),
          ),
        ],
      ],
    );
  }

  void _onPublicRoomTap(BuildContext context, PublishedRoomsChunk chunk) {
    final address = chunk.canonicalAlias?.toString() ?? chunk.roomId;
    context.push('/v2/join-room/${Uri.encodeComponent(address)}');
  }

  /// 点击搜索到的用户 → 打开其 V2 个人资料页
  void _onUserTap(BuildContext context, Profile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileV2(userId: profile.userId),
      ),
    );
  }
}

/// 搜索结果分组标题
class _SearchSectionHeader extends StatelessWidget {
  final String title;
  const _SearchSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: V2Theme.of(context).scaffoldBackground,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: V2Theme.of(context).textSecondary,
        ),
      ),
    );
  }
}

/// 公开房间搜索结果项
class _PublicRoomResultTile extends StatelessWidget {
  final PublishedRoomsChunk chunk;
  final VoidCallback onTap;
  const _PublicRoomResultTile({required this.chunk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = chunk.name ?? chunk.canonicalAlias?.localpart ?? l10n.group;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Avatar(mxContent: chunk.avatarUrl, name: name, size: 44),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    '${chunk.numJoinedMembers} ${l10n.members}',
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ],
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
    );
  }
}

/// 用户搜索结果项
class _UserResultTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;
  const _UserResultTile({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = profile.displayName ?? profile.userId.localpart ?? l10n.user;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Avatar(mxContent: profile.avatarUrl, name: name, size: 44),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    profile.userId,
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

/// 本地房间搜索结果项
class _LocalRoomResultTile extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  final String? subtitle;
  const _LocalRoomResultTile({
    required this.room,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return FutureBuilder(
      future: room.name.isEmpty ? room.loadHeroUsers() : null,
      builder: (context, _) {
        final name = room.getLocalizedDisplayname();
        final sub = subtitle ??
            (room.isDirectChat
                ? (room.lastEvent != null
                    ? l10n.recentlyOnline
                    : l10n.lastSeenLongAgo)
                : l10n
                    .membersCount(room.summary.mJoinedMemberCount ?? 0));
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Avatar(mxContent: room.avatar, name: name, size: 44),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        sub,
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
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: V2Theme.of(context).textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
