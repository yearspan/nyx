import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_check_button.dart';
import 'package:fluffychat/widgets_v2/v2_search_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 成员选择弹窗的数据源 / 行为模式
enum InviteMembersMode {
  /// 邀请新成员：数据源为联系人 + 用户目录搜索，确认时执行邀请
  invite,

  /// 从群成员中选择：数据源为当前群已加入成员，确认时回调外部处理
  /// （如设为管理员 / 协管员）
  selectMembers,

  /// 转发消息：数据源为所有可发消息的房间（群聊 + 私信），
  /// 确认时通过 [onConfirm] 回调房间 ID 列表
  forward,
}

/// V2 成员选择弹窗（可复用）
///
/// 白底、搜索框、按字母分组的联系人列表，每项展示头像/昵称/状态，
/// 右侧为复选框。
///
/// 三种模式：
/// - [InviteMembersMode.invite]：邀请新成员入群（默认）
/// - [InviteMembersMode.selectMembers]：从群成员中选择，确认后通过
///   [onConfirm] 回调交给调用方处理（如设为管理员）
/// - [InviteMembersMode.forward]：选择转发目标房间，确认后通过
///   [onConfirm] 回调房间 ID 列表
///
/// 用法：
/// ```dart
/// // 邀请新成员
/// InviteMembersV2.show(context, roomId: room.id);
///
/// // 从群成员中选择
/// InviteMembersV2.show(
///   context,
///   roomId: room.id,
///   mode: InviteMembersMode.selectMembers,
///   title: '添加管理员',
///   disabledUserIds: {'@owner:server', ...},
///   onConfirm: (ids) async { ... },
/// );
///
/// // 转发消息到房间
/// InviteMembersV2.show(
///   context,
///   roomId: room.id,
///   mode: InviteMembersMode.forward,
///   title: '转发到',
///   onConfirm: (roomIds) async { ... },
/// );
/// ```
class InviteMembersV2 extends StatefulWidget {
  final String roomId;

  /// 选择模式，默认 [InviteMembersMode.invite]
  final InviteMembersMode mode;

  /// 弹窗标题，默认取 [L10n.addMembers]
  final String? title;

  /// 搜索框提示文案
  final String? hintText;

  /// 已禁用（不可选）的成员 ID 集合，仅 [InviteMembersMode.selectMembers] 使用
  final Set<String>? disabledUserIds;

  /// 选择确认回调，仅 [InviteMembersMode.selectMembers] 使用；
  /// 为空时使用默认邀请逻辑。
  final Future<void> Function(List<String> userIds)? onConfirm;

  const InviteMembersV2({
    super.key,
    required this.roomId,
    this.mode = InviteMembersMode.invite,
    this.title,
    this.hintText,
    this.disabledUserIds,
    this.onConfirm,
  });

  /// 以底部弹窗形式展示成员选择面板
  static Future<void> show(
    BuildContext context, {
    required String roomId,
    InviteMembersMode mode = InviteMembersMode.invite,
    String? title,
    String? hintText,
    Set<String>? disabledUserIds,
    Future<void> Function(List<String> userIds)? onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InviteMembersV2(
        roomId: roomId,
        mode: mode,
        title: title,
        hintText: hintText,
        disabledUserIds: disabledUserIds,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<InviteMembersV2> createState() => _InviteMembersV2State();
}

class _InviteMembersV2State extends State<InviteMembersV2> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _coolDown;
  bool _loading = false;
  bool _inviting = false;
  List<Profile> _foundProfiles = [];

  /// selectMembers 模式下从群成员中加载的参与者
  List<User>? _participants;

  /// forward 模式下可转发的房间列表
  List<Room>? _forwardRooms;

  /// 已勾选的用户 ID 集合
  final Set<String> _selectedUserIds = {};

  /// 每个字母分组对应的 GlobalKey，供右侧索引栏点击滚动定位
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.mode == InviteMembersMode.selectMembers) {
      _loadParticipants();
    } else if (widget.mode == InviteMembersMode.forward) {
      _loadForwardRooms();
    } else {
      // invite 模式：预加载群成员，确保已在群里的用户被禁用
      _loadRoomMembers();
    }
  }

  /// invite 模式：拉取群成员列表填充 SDK 缓存，
  /// 使 `_memberIds`（getParticipants）能正确返回已加入成员
  Future<void> _loadRoomMembers() async {
    final room = _room;
    if (room == null) return;
    try {
      await room.requestParticipants([Membership.join]);
      if (mounted) setState(() {});
    } catch (_) {
      // 拉取失败时保持现状
    }
  }

  Future<void> _loadParticipants() async {
    final room = _room;
    if (room == null) return;
    try {
      final participants = await room.requestParticipants([Membership.join]);
      if (mounted) setState(() => _participants = participants);
    } catch (_) {
      if (mounted) setState(() => _participants = const []);
    }
  }

  /// forward 模式：加载所有可发消息的已加入房间（群聊 + 私信）
  void _loadForwardRooms() {
    final client = Matrix.of(context).client;
    final rooms = client.rooms
        .where(
          (r) =>
              r.canSendDefaultMessages &&
              !r.isSpace &&
              r.membership == Membership.join,
        )
        .toList();
    setState(() => _forwardRooms = rooms);
  }

  @override
  void dispose() {
    _coolDown?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Room? get _room => Matrix.of(context).client.getRoomById(widget.roomId);

  /// 是否为「从群成员中选择」模式
  bool get _selectMode => widget.mode == InviteMembersMode.selectMembers;

  /// 是否为「转发」模式
  bool get _forwardMode => widget.mode == InviteMembersMode.forward;

  /// 当前群已加入/已邀请的成员 ID 集合（仅 invite 模式用于禁用）
  Set<String> get _memberIds {
    final room = _room;
    if (room == null) return {};
    return room.getParticipants().map((u) => u.id).toSet();
  }

  /// 禁用的用户 ID 集合
  ///
  /// 优先使用外部传入的 [widget.disabledUserIds]（例如屏蔽用户场景下
  /// 禁用已屏蔽用户）；未提供时，selectMembers 模式不禁用任何人，
  /// invite 模式禁用当前房间已加入的成员。
  Set<String> get _disabledIds =>
      widget.disabledUserIds ?? (_selectMode ? const <String>{} : _memberIds);

  /// 根据名称获取分组首字母
  /// - A-Z 开头：直接用该字母
  /// - 中文开头：取拼音首字母
  /// - 其他（数字、符号等）：归入 #
  String _firstLetter(String name) {
    if (name.isEmpty) return '#';
    final first = name[0];
    // 已是拉丁字母
    final upper = first.toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(upper)) return upper;
    // 中文 → 拼音首字母
    final pinyin = PinyinHelper.getShortPinyin(first);
    if (pinyin.isNotEmpty) {
      final pl = pinyin[0].toUpperCase();
      if (RegExp(r'[A-Z]').hasMatch(pl)) return pl;
    }
    return '#';
  }

  /// selectMembers 模式：群成员按首字母分组（已过滤掉不可选的成员）
  Map<String, List<User>> get _groupedParticipants {
    final disabled = _selectMode ? _disabledIds : const <String>{};
    final participants = (_participants ?? const <User>[])
        .where((u) => !disabled.contains(u.id))
        .toList();
    final map = <String, List<User>>{};
    for (final user in participants) {
      final name = user.calcDisplayname().trim();
      final key = _firstLetter(name);
      map.putIfAbsent(key, () => []).add(user);
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final pa = PinyinHelper.getPinyin(a.calcDisplayname());
        final pb = PinyinHelper.getPinyin(b.calcDisplayname());
        return pa.compareTo(pb);
      });
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return {for (final k in sortedKeys) k: map[k]!};
  }

  /// invite 模式：联系人（DM 的对方）按首字母分组
  Map<String, List<User>> get _groupedContacts {
    final client = Matrix.of(context).client;
    final contacts = client.rooms
        .where(
          (r) =>
              !r.isSpace && r.isDirectChat && r.membership == Membership.join,
        )
        .map((r) => r.unsafeGetUserFromMemoryOrFallback(r.directChatMatrixID!))
        .toList();
    final map = <String, List<User>>{};
    for (final user in contacts) {
      final name = user.calcDisplayname().trim();
      final key = _firstLetter(name);
      map.putIfAbsent(key, () => []).add(user);
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final pa = PinyinHelper.getPinyin(a.calcDisplayname());
        final pb = PinyinHelper.getPinyin(b.calcDisplayname());
        return pa.compareTo(pb);
      });
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return {for (final k in sortedKeys) k: map[k]!};
  }

  /// forward 模式：可转发的房间按首字母分组
  Map<String, List<Room>> get _groupedForwardRooms {
    final rooms = _forwardRooms ?? const <Room>[];
    final map = <String, List<Room>>{};
    final l10n = L10n.of(context);
    for (final room in rooms) {
      final name = room.getLocalizedDisplayname(MatrixLocals(l10n)).trim();
      final key = _firstLetter(name);
      map.putIfAbsent(key, () => []).add(room);
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final pa = PinyinHelper.getPinyin(
          a.getLocalizedDisplayname(MatrixLocals(l10n)),
        );
        final pb = PinyinHelper.getPinyin(
          b.getLocalizedDisplayname(MatrixLocals(l10n)),
        );
        return pa.compareTo(pb);
      });
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return {for (final k in sortedKeys) k: map[k]!};
  }

  void _onSearchChanged(String text) {
    if (_selectMode || _forwardMode) {
      // selectMembers / forward 模式下本地过滤，无需防抖请求
      setState(() {});
      return;
    }
    _coolDown?.cancel();
    _coolDown = Timer(
      const Duration(milliseconds: 500),
      () => _searchUser(text),
    );
  }

  /// invite 模式：用户目录搜索
  Future<void> _searchUser(String text) async {
    _coolDown?.cancel();
    if (text.isEmpty) {
      setState(() => _foundProfiles = []);
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final response = await Matrix.of(
        context,
      ).client.searchUserDirectory(text, limit: 10);
      final results = List<Profile>.from(response.results);
      if (text.isValidMatrixIdStrict() &&
          results.indexWhere((p) => text == p.userId) == -1) {
        results.insert(0, Profile.fromJson({'user_id': text}));
      }
      if (mounted) setState(() => _foundProfiles = results);
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 切换某个用户的选中状态
  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  /// 确认按钮回调：根据模式执行邀请或外部回调
  /// 若提供了 [onConfirm] 回调，则优先调用回调（用于新建群聊等需要先
  /// 获取选中成员再执行后续操作的场景），不再自行邀请。
  Future<void> _confirmSelected() async {
    if (_selectedUserIds.isEmpty || _inviting) return;
    final l10n = L10n.of(context);
    setState(() => _inviting = true);
    try {
      if (widget.onConfirm != null) {
        await widget.onConfirm!(_selectedUserIds.toList());
      } else if (_selectMode || _forwardMode) {
        await widget.onConfirm?.call(_selectedUserIds.toList());
      } else {
        final room = _room;
        if (room == null) {
          if (mounted) {
            V2Toast.show(l10n.oopsSomethingWentWrong);
          }
        } else {
          // 逐个邀请，失败不阻塞其他
          for (final userId in _selectedUserIds.toList()) {
            try {
              await room.invite(userId);
            } catch (_) {
              // 忽略单个失败
            }
          }
          if (mounted) {
            V2Toast.show(l10n.contactHasBeenInvitedToTheGroup);
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
        // 邀请/选择完成后关闭弹窗
        Navigator.of(context).pop();
      }
    }
  }

  /// 根据在线状态返回副标题文案
  String _statusForUser(User user) {
    final presence = user.presence?.presence;
    final l10n = L10n.of(context);
    if (presence == null) return l10n.lastSeenLongAgo;
    if (presence.currentlyActive == true) return l10n.recentlyOnline;
    final lastActiveAgo = presence.lastActiveAgo;
    if (lastActiveAgo != null &&
        Duration(milliseconds: lastActiveAgo).inDays < 7) {
      return l10n.recentlyOnline;
    }
    return l10n.lastSeenLongAgo;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = _room;
    final isSearching = _searchController.text.trim().isNotEmpty;
    final title = widget.title ?? l10n.addMembers;
    final hintText = widget.hintText ?? l10n.search;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        child: Scaffold(
          backgroundColor: V2Theme.of(context).cardBackground,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                // 顶部拖动指示条
                Center(
                  child: Container(
                    margin: EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 顶部栏：关闭 + 标题 + 确定
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: SizedBox(
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          child: V2CircleIconButton(
                            icon: Icons.close,
                            iconColor: Theme.of(context).colorScheme.onSurface,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          child: V2CheckButton(
                            onTap: _confirmSelected,
                            isLoading: _inviting,
                            enabled: _selectedUserIds.isNotEmpty,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                V2SearchBar(
                  controller: _searchController,
                  hintText: hintText,
                  onChanged: _onSearchChanged,
                ),
                Expanded(
                  child: _forwardMode
                      ? (isSearching
                            ? _buildSearchResults(null)
                            : Stack(
                                children: [
                                  _buildForwardRoomsList(),
                                  _buildIndexBar(),
                                ],
                              ))
                      : _selectMode && room == null
                      ? Center(
                          child: Text(
                            l10n.youAreNoLongerParticipatingInThisChat,
                          ),
                        )
                      : isSearching
                      ? _buildSearchResults(room)
                      : _selectMode
                      ? _buildSelectMembersList()
                      : Stack(
                          children: [_buildContactList(room), _buildIndexBar()],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(Room? room) {
    if (_forwardMode) {
      // forward 模式：本地过滤房间
      final keyword = _searchController.text.trim().toLowerCase();
      final l10n = L10n.of(context);
      final rooms = _forwardRooms ?? const <Room>[];
      final filtered = rooms
          .where(
            (r) => r
                .getLocalizedDisplayname(MatrixLocals(l10n))
                .toLowerCase()
                .contains(keyword),
          )
          .toList();
      if (filtered.isEmpty) {
        return Center(
          child: Text(
            l10n.userNotFound,
            style: TextStyle(color: V2Theme.of(context).textSecondary),
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final r = filtered[i];
          return _RoomTile(
            room: r,
            selected: _selectedUserIds.contains(r.id),
            onChanged: () => _toggleSelection(r.id),
          );
        },
      );
    }
    if (_selectMode) {
      // selectMembers 模式：本地过滤群成员
      final keyword = _searchController.text.trim().toLowerCase();
      final participants = _participants ?? const <User>[];
      final disabled = _disabledIds;
      final filtered = participants
          .where((u) => !disabled.contains(u.id))
          .where(
            (u) =>
                u.calcDisplayname().toLowerCase().contains(keyword) ||
                u.id.toLowerCase().contains(keyword),
          )
          .toList();
      if (filtered.isEmpty) {
        return Center(
          child: Text(
            L10n.of(context).userNotFound,
            style: TextStyle(color: V2Theme.of(context).textSecondary),
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final user = filtered[i];
          return _ContactTile(
            avatarUrl: user.avatarUrl,
            name: user.calcDisplayname(),
            status: user.id,
            isMember: false,
            selected: _selectedUserIds.contains(user.id),
            onChanged: () => _toggleSelection(user.id),
          );
        },
      );
    }
    if (_loading) {
      return Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2));
    }
    if (_foundProfiles.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).userNotFound,
          style: TextStyle(color: V2Theme.of(context).textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: _foundProfiles.length,
      itemBuilder: (context, i) {
        final profile = _foundProfiles[i];
        return _ContactTile(
          avatarUrl: profile.avatarUrl,
          name:
              profile.displayName ??
              profile.userId.localpart ??
              L10n.of(context).user,
          status: profile.userId,
          isMember: _disabledIds.contains(profile.userId),
          selected: _selectedUserIds.contains(profile.userId),
          onChanged: () => _toggleSelection(profile.userId),
        );
      },
    );
  }

  /// selectMembers 模式：群成员分组列表
  Widget _buildSelectMembersList() {
    final participants = _participants;
    if (participants == null) {
      return Center(child: CircularProgressIndicator());
    }
    if (participants.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).userNotFound,
          style: TextStyle(color: V2Theme.of(context).textSecondary),
        ),
      );
    }
    final disabled = _disabledIds;
    final grouped = _groupedParticipants;
    for (final key in grouped.keys) {
      _sectionKeys.putIfAbsent(key, GlobalKey.new);
    }
    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          padding: EdgeInsets.only(left: 16, right: 40, top: 4),
          children: [
            for (final entry in grouped.entries) ...[
              Padding(
                key: _sectionKeys[entry.key],
                padding: EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: V2Theme.of(context).textSecondary,
                  ),
                ),
              ),
              for (final user in entry.value)
                _ContactTile(
                  avatarUrl: user.avatarUrl,
                  name: user.calcDisplayname(),
                  status: user.id,
                  isMember: disabled.contains(user.id),
                  selected: _selectedUserIds.contains(user.id),
                  onChanged: () => _toggleSelection(user.id),
                ),
            ],
            SizedBox(height: 24),
          ],
        ),
        _buildIndexBar(),
      ],
    );
  }

  Widget _buildContactList(Room? room) {
    final grouped = _groupedContacts;
    for (final key in grouped.keys) {
      _sectionKeys.putIfAbsent(key, GlobalKey.new);
    }
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(left: 16, right: 40, top: 4),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            key: _sectionKeys[entry.key],
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
          ),
          for (final user in entry.value)
            _ContactTile(
              avatarUrl: user.avatarUrl,
              name: user.calcDisplayname(),
              status: _statusForUser(user),
              isMember: _disabledIds.contains(user.id),
              selected: _selectedUserIds.contains(user.id),
              onChanged: () => _toggleSelection(user.id),
            ),
        ],
        SizedBox(height: 24),
      ],
    );
  }

  /// forward 模式：可转发房间分组列表
  Widget _buildForwardRoomsList() {
    final rooms = _forwardRooms;
    if (rooms == null) {
      return Center(child: CircularProgressIndicator());
    }
    if (rooms.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).userNotFound,
          style: TextStyle(color: V2Theme.of(context).textSecondary),
        ),
      );
    }
    final grouped = _groupedForwardRooms;
    for (final key in grouped.keys) {
      _sectionKeys.putIfAbsent(key, GlobalKey.new);
    }
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(left: 16, right: 40, top: 4),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            key: _sectionKeys[entry.key],
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
          ),
          for (final room in entry.value)
            _RoomTile(
              room: room,
              selected: _selectedUserIds.contains(room.id),
              onChanged: () => _toggleSelection(room.id),
            ),
        ],
        SizedBox(height: 24),
      ],
    );
  }

  /// 点击右侧索引字母 → 滚动到对应分组
  void _scrollToLetter(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  /// 右侧 A-Z 索引栏（微信风格）
  Widget _buildIndexBar() {
    final keys = _sectionKeys.keys.toList();
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(right: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final letter in keys)
              GestureDetector(
                onTap: () => _scrollToLetter(letter),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 联系人列表项：左侧复选框 + 头像 + 昵称 + 状态
class _ContactTile extends StatelessWidget {
  final Uri? avatarUrl;
  final String name;
  final String status;
  final bool isMember;
  final bool selected;
  final VoidCallback onChanged;

  const _ContactTile({
    required this.avatarUrl,
    required this.name,
    required this.status,
    required this.isMember,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = isMember;
    final checkColor = selected
        ? V2Theme.of(context).accent
        : V2Theme.of(context).divider;
    return GestureDetector(
      onTap: disabled ? null : onChanged,
      child: Container(
        color: Colors.transparent,
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // 复选框
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? V2Theme.of(context).accent
                    : Colors.transparent,
                border: selected
                    ? null
                    : Border.all(
                        color: disabled
                            ? checkColor
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(.6),
                        width: 1.5,
                      ),
              ),
              child: selected
                  ? Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
            SizedBox(width: 12),
            Avatar(mxContent: avatarUrl, name: name, size: 44),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: disabled
                          ? V2Theme.of(context).textSecondary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    status,
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

/// 房间列表项（forward 模式）：左侧复选框 + 房间头像 + 房间名 + 成员数
class _RoomTile extends StatelessWidget {
  final Room room;
  final bool selected;
  final VoidCallback onChanged;

  const _RoomTile({
    required this.room,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = room.getLocalizedDisplayname(MatrixLocals(l10n));
    final memberCount =
        (room.summary.mJoinedMemberCount ?? 0) +
        (room.summary.mInvitedMemberCount ?? 0);
    final subtitle = room.isDirectChat
        ? (room.directChatMatrixID ?? '')
        : l10n.countParticipants(memberCount);
    final checkColor = selected
        ? V2Theme.of(context).accent
        : V2Theme.of(context).divider;
    return GestureDetector(
      onTap: onChanged,
      child: Container(
        color: Colors.transparent,
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? V2Theme.of(context).accent
                    : Colors.transparent,
                border: Border.all(color: checkColor, width: 1.5),
              ),
              child: selected
                  ? Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
            SizedBox(width: 12),
            Avatar(mxContent: room.avatar, name: name, size: 44),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
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
                    subtitle,
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
