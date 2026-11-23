import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2 权限页
///
/// 入口：群设置 → 角色与权限 → 权限
/// 将群权限按「管理成员 / 编辑社区 / 消息和内容」三组展示，
/// 每项可选择「仅限管理员 / 管理员和协管员 / 成员」三个等级。
/// 只有群主和管理员（可修改 power levels）可以编辑。
class RoomPermissionsV2 extends StatefulWidget {
  final String roomId;

  const RoomPermissionsV2({super.key, required this.roomId});

  @override
  State<RoomPermissionsV2> createState() => _RoomPermissionsV2State();
}

class _RoomPermissionsV2State extends State<RoomPermissionsV2> {
  Room get _room => Matrix.of(context).client.getRoomById(widget.roomId)!;

  /// 是否可编辑权限（群主 / 管理员，权限等级 >= 100）。
  /// 注意不能用 `canChangePowerLevel`：该方法回退到 `state_default`（默认 50，即协管员级），
  /// 会导致协管员也能修改权限。
  bool get _canEdit =>
      _room.ownPowerLevel.level >= PowerLevel.defaultAdminLevel;

  StreamSubscription? _roomStateSub;

  @override
  void initState() {
    super.initState();
    final client = Matrix.of(context).client;
    _roomStateSub = client.onRoomState.stream
        .where(
          (e) =>
              e.roomId == widget.roomId &&
              e.state.type == EventTypes.RoomPowerLevels,
        )
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _roomStateSub?.cancel();
    super.dispose();
  }

  /// 当前群的 power levels 内容
  Map<String, Object?> get _content =>
      Map<String, Object?>.from(
        _room.getState(EventTypes.RoomPowerLevels)?.content ?? {},
      );

  /// 读取顶层字段的权限等级，缺失时回退到 [fallback]
  int _topLevel(String key, int fallback) =>
      _content.tryGet<int>(key) ?? fallback;

  /// 读取 events 映射中某个事件类型的权限等级，
  /// 缺失时回退到 state_default，再缺失回退到 [fallback]
  int _eventLevel(String eventType, int fallback) {
    final events = _content.tryGetMap<String, Object?>('events');
    if (events != null && events.containsKey(eventType)) {
      return events[eventType] as int? ?? fallback;
    }
    return _content.tryGet<int>('state_default') ?? fallback;
  }

  /// 把整数等级转为三档显示文案
  String _levelLabel(int level, L10n l10n) {
    if (level >= PowerLevel.defaultAdminLevel) return l10n.adminsOnly;
    if (level >= PowerLevel.defaultModeratorLevel) {
      return l10n.adminsAndModerators;
    }
    return l10n.members;
  }

  /// 权限项定义
  List<_PermissionGroup> _groups(L10n l10n) => [
        _PermissionGroup(
          title: l10n.manageMembers,
          items: [
            _PermissionItem(
              label: l10n.inviteMembers,
              level: _topLevel('invite', PowerLevel.defaultUserLevel),
              onApply: (lvl) => _setTopLevel('invite', lvl),
            ),
            _PermissionItem(
              label: l10n.removeMembers,
              level: _topLevel('kick', PowerLevel.defaultModeratorLevel),
              onApply: (lvl) => _setTopLevel('kick', lvl),
            ),
            _PermissionItem(
              label: l10n.banMembers,
              level: _topLevel('ban', PowerLevel.defaultModeratorLevel),
              onApply: (lvl) => _setTopLevel('ban', lvl),
            ),
          ],
        ),
        _PermissionGroup(
          title: l10n.editCommunity,
          items: [
            _PermissionItem(
              label: l10n.changeCommunityName,
              level: _eventLevel(
                EventTypes.RoomName,
                PowerLevel.defaultModeratorLevel,
              ),
              onApply: (lvl) => _setEventLevel(EventTypes.RoomName, lvl),
            ),
            _PermissionItem(
              label: l10n.changeCommunityAvatar,
              level: _eventLevel(
                EventTypes.RoomAvatar,
                PowerLevel.defaultModeratorLevel,
              ),
              onApply: (lvl) => _setEventLevel(EventTypes.RoomAvatar, lvl),
            ),
            _PermissionItem(
              label: l10n.changeCommunityDescription,
              level: _eventLevel(
                EventTypes.RoomTopic,
                PowerLevel.defaultModeratorLevel,
              ),
              onApply: (lvl) => _setEventLevel(EventTypes.RoomTopic, lvl),
            ),
          ],
        ),
        _PermissionGroup(
          title: l10n.messagesAndContent,
          items: [
            _PermissionItem(
              label: l10n.sendMessages,
              level: _topLevel('events_default', PowerLevel.defaultUserLevel),
              onApply: (lvl) => _setTopLevel('events_default', lvl),
            ),
            _PermissionItem(
              label: l10n.removeMessages,
              level: _topLevel('redact', PowerLevel.defaultModeratorLevel),
              onApply: (lvl) => _setTopLevel('redact', lvl),
            ),
          ],
        ),
      ];

  /// 更新顶层字段权限等级
  Future<void> _setTopLevel(String key, int level) async {
    final content = _content;
    content[key] = level;
    await _commit(content);
  }

  /// 更新 events 映射中某个事件类型的权限等级
  Future<void> _setEventLevel(String eventType, int level) async {
    final content = _content;
    var events = content.tryGetMap<String, Object?>('events');
    if (events == null) {
      events = <String, Object?>{};
      content['events'] = events;
    }
    events[eventType] = level;
    await _commit(content);
  }

  /// 提交 power levels 状态事件并更新本地缓存
  Future<void> _commit(Map<String, Object?> content) async {
    final me = _room.client.userID;
    try {
      await _room.client.setRoomStateWithKey(
        _room.id,
        EventTypes.RoomPowerLevels,
        '',
        content,
      );
      // 手动更新本地状态，无需等待下一次 sync
      _room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          senderId: me ?? '',
          content: content,
        ),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) V2Toast.show(e.toString());
    }
  }

  /// 弹出底部选择面板，返回用户选择的等级
  Future<int?> _showLevelPicker(int currentLevel) {
    final l10n = L10n.of(context);
    final options = <({int level, String label})>[
      (level: PowerLevel.defaultAdminLevel, label: l10n.adminsOnly),
      (
        level: PowerLevel.defaultModeratorLevel,
        label: l10n.adminsAndModerators,
      ),
      (level: PowerLevel.defaultUserLevel, label: l10n.members),
    ];
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LevelPickerSheet(
        options: options,
        currentLevel: currentLevel,
      ),
    );
  }

  /// 点击某权限项 → 弹出选择面板 → 应用新等级
  Future<void> _onItemTap(_PermissionItem item) async {
    if (!_canEdit) {
      V2Toast.show(L10n.of(context).noPermission);
      return;
    }
    final newLevel = await _showLevelPicker(item.level);
    if (newLevel == null || newLevel == item.level) return;
    await item.onApply(newLevel);
  }

  /// 重置权限为 Matrix 默认值
  Future<void> _resetPermissions() async {
    final l10n = L10n.of(context);
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.resetPermissions,
      message: l10n.resetPermissionsConfirmMessage,
      confirmLabel: l10n.resetPermissions,
    );
    if (confirmed != true) return;

    final content = _content;
    // 管理成员
    content['invite'] = PowerLevel.defaultUserLevel;
    content['kick'] = PowerLevel.defaultModeratorLevel;
    content['ban'] = PowerLevel.defaultModeratorLevel;
    // 消息和内容
    content['redact'] = PowerLevel.defaultModeratorLevel;
    content['events_default'] = PowerLevel.defaultUserLevel;
    // 编辑社区（events 映射）
    var events = content.tryGetMap<String, Object?>('events');
    if (events == null) {
      events = <String, Object?>{};
      content['events'] = events;
    }
    events[EventTypes.RoomName] = PowerLevel.defaultModeratorLevel;
    events[EventTypes.RoomAvatar] = PowerLevel.defaultModeratorLevel;
    events[EventTypes.RoomTopic] = PowerLevel.defaultModeratorLevel;
    await _commit(content);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final groups = _groups(l10n);

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(
            title: l10n.permissions,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (var gi = 0; gi < groups.length; gi++) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: Text(
                      groups[gi].title,
                      style: TextStyle(
                        fontSize: 13,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).cardBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var ii = 0;
                            ii < groups[gi].items.length;
                            ii++) ...[
                          _PermissionTile(
                            item: groups[gi].items[ii],
                            canEdit: _canEdit,
                            levelLabel: _levelLabel(
                              groups[gi].items[ii].level,
                              l10n,
                            ),
                            onTap: () => _onItemTap(groups[gi].items[ii]),
                          ),
                          if (ii < groups[gi].items.length - 1)
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: V2Theme.of(context).divider,
                              indent: 16,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 24),
                // 重置权限
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: _canEdit ? _resetPermissions : null,
                    style: TextButton.styleFrom(
                      foregroundColor: Color(0xFFFF4D4F),
                      backgroundColor: V2Theme.of(context).cardBackground,
                      disabledForegroundColor:
                          Color(0xFFFF4D4F).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      l10n.resetPermissions,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 权限分组
class _PermissionGroup {
  final String title;
  final List<_PermissionItem> items;

  const _PermissionGroup({required this.title, required this.items});
}

/// 单个权限项
class _PermissionItem {
  final String label;
  final int level;
  final Future<void> Function(int level) onApply;

  const _PermissionItem({
    required this.label,
    required this.level,
    required this.onApply,
  });
}

/// 权限列表项
class _PermissionTile extends StatelessWidget {
  final _PermissionItem item;
  final bool canEdit;
  final String levelLabel;
  final VoidCallback onTap;

  const _PermissionTile({
    required this.item,
    required this.canEdit,
    required this.levelLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = !canEdit;
    return InkWell(
      onTap: disabled ? null : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 15,
                  color: disabled
                      ? V2Theme.of(context).textSecondary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Text(
              levelLabel,
              style: TextStyle(
                fontSize: 14,
                color: disabled
                    ? V2Theme.of(context).textSecondary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: disabled
                  ? V2Theme.of(context).textSecondary
                  : V2Theme.of(context).textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 等级选择底部面板
class _LevelPickerSheet extends StatelessWidget {
  final List<({int level, String label})> options;
  final int currentLevel;

  const _LevelPickerSheet({
    required this.options,
    required this.currentLevel,
  });

  @override
  Widget build(BuildContext context) {
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
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  options[i].label,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (options[i].level == currentLevel)
                                Icon(
                                  Icons.check,
                                  size: 22,
                                  color: V2Theme.of(context).accent,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (i < options.length - 1)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: V2Theme.of(context).divider,
                          indent: 16,
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
                    L10n.of(context).cancel,
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
