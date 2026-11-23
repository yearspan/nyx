import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/settings_v2/notifications_v2.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_advanced_switch/flutter_advanced_switch.dart';
import 'package:matrix/matrix.dart';

/// 单个聊天（群聊/私聊）的消息通知设置页
class NotificationRoomV2 extends StatefulWidget {
  final String roomId;
  const NotificationRoomV2({super.key, required this.roomId});

  @override
  State<NotificationRoomV2> createState() => _NotificationRoomV2State();
}

class _NotificationRoomV2State extends State<NotificationRoomV2> {
  StreamSubscription<BasicEvent>? _accountDataSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 监听推送规则变更（通过 account_data 同步），实时刷新界面
      _accountDataSub =
          // ignore: deprecated_member_use
          Matrix.of(context).client.onAccountData.stream.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _accountDataSub?.cancel();
    super.dispose();
  }

  Client get _client => Matrix.of(context).client;
  Room? get _room => _client.getRoomById(widget.roomId);
  PushRuleSet? get _rules => _client.globalPushRules;

  /// 取该房间在指定类别下的推送规则
  PushRule? _ruleOf(PushRuleKind kind) {
    final list = switch (kind) {
      PushRuleKind.override => _rules?.override,
      PushRuleKind.room => _rules?.room,
      _ => null,
    };
    for (final r in list ?? const <PushRule>[]) {
      if (r.ruleId == widget.roomId) return r;
    }
    return null;
  }

  /// 去掉 dont_notify / coalesce 后的有效动作（与 SDK pushRuleState 判定一致）
  List<Object?> _effectiveActions(PushRule rule) => rule.actions
      .where((a) => a != 'dont_notify' && a != 'coalesce')
      .toList();

  /// 是否静音：override 类别存在该房间规则且动作空。
  /// 静音只用 override 规则，与「通知模式」(room 规则) 相互独立。
  bool get _muted {
    final rule = _ruleOf(PushRuleKind.override);
    return rule != null && _effectiveActions(rule).isEmpty;
  }

  /// 通知模式：room 类别规则。动作空 = 仅提及，否则（含默认无规则）= 所有消息
  NotificationMode get _mode {
    final roomRule = _ruleOf(PushRuleKind.room);
    if (roomRule == null) return NotificationMode.allMessages;
    return _effectiveActions(roomRule).isEmpty
        ? NotificationMode.mentionsOnly
        : NotificationMode.allMessages;
  }

  /// 是否存在该房间的独立推送规则（room 或 override 类别中）
  bool get _hasCustomSettings =>
      _ruleOf(PushRuleKind.room) != null ||
      _ruleOf(PushRuleKind.override) != null;

  /// 开启自定义设置：写入一条 room 类别的「所有消息」规则
  Future<void> _enableCustomSettings(bool enable) async {
    if (enable) {
      await _safe(
        () => _client.setPushRule(
          PushRuleKind.room,
          widget.roomId,
          <Object?>['notify'],
        ),
      );
    } else {
      await _resetIndependent();
    }
    if (mounted) setState(() {});
  }

  /// 切换通知模式：只写 room 规则，不动静音的 override 规则
  Future<void> _setMode(NotificationMode mode) async {
    await _safe(
      () => _client.setPushRule(
        PushRuleKind.room,
        widget.roomId,
        mode == NotificationMode.allMessages
            ? <Object?>['notify']
            : const <Object?>[],
      ),
    );
    if (mounted) setState(() {});
  }

  /// 切换静音：只增删 override 规则，不动已选模式的 room 规则。
  /// 这样静音/取消静音不会改变 _hasCustomSettings，自定义总开关就不会跳。
  Future<void> _toggleMute(bool muted) async {
    await _safe(() async {
      if (muted) {
        await _client.setPushRule(
          PushRuleKind.override,
          widget.roomId,
          const <Object?>[],
          conditions: [
            PushCondition(
              kind: PushRuleConditions.eventMatch.name,
              key: 'room_id',
              pattern: widget.roomId,
            ),
          ],
        );
      } else {
        await _client.deletePushRule(PushRuleKind.override, widget.roomId);
      }
    });
    if (mounted) setState(() {});
  }

  /// 撤销独立设置：删除该房间的 room / override 推送规则（不关闭页面）
  Future<void> _resetIndependent() async {
    final client = Matrix.of(context).client;
    try {
      await client.deletePushRule(PushRuleKind.room, widget.roomId);
    } catch (_) {}
    try {
      await client.deletePushRule(PushRuleKind.override, widget.roomId);
    } catch (_) {}
  }

  Future<void> _safe(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = _room;
    final customEnabled = _hasCustomSettings;
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.messageNotifications),//room?.getLocalizedDisplayname() ??
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: 12, bottom: 40),
              children: [
                // 允许自定义设置（总开关）
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: V2Theme.of(context).cardBackground,
                    borderRadius: BorderRadius.circular(V2Theme.cardRadius),
                  ),
                  child: _MasterSwitchTile(
                    value: customEnabled,
                    onToggle: _enableCustomSettings,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    l10n.enableThisWillOverrideDefault,
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ),
                if (customEnabled) ...[
                  SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      l10n.notifyMeInThisChat,
                      style: TextStyle(
                        fontSize: 13,
                        color: V2Theme.of(context).textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).cardBackground,
                      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
                    ),
                    child: Column(
                      children: [
                        _RadioTile(
                          title: l10n.allMessages,
                          selected: !_muted &&
                              _mode == NotificationMode.allMessages,
                          onTap: () =>
                              _setMode(NotificationMode.allMessages),
                        ),
                        const _Divider(),
                        _RadioTile(
                          title: l10n.mentionsAndKeywordsRoom,
                          subtitle: l10n.mentionsAndKeywordsSubtitleRoom,
                          selected: !_muted &&
                              _mode == NotificationMode.mentionsOnly,
                          onTap: () =>
                              _setMode(NotificationMode.mentionsOnly),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  // 静音
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).cardBackground,
                      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
                    ),
                    child: _MuteTile(
                      value: _muted,
                      onToggle: _toggleMute,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部「允许自定义设置」开关行
class _MasterSwitchTile extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onToggle;
  const _MasterSwitchTile({required this.value, required this.onToggle});

  @override
  State<_MasterSwitchTile> createState() => _MasterSwitchTileState();
}

class _MasterSwitchTileState extends State<_MasterSwitchTile> {
  late final ValueNotifier<bool> _controller;

  /// 外部状态同步时赋值只更新显示，不触发 [onToggle]，避免 build 阶段
  /// （didUpdateWidget）回调里 setState 抛 "setState() called during build"。
  bool _programmaticallyUpdating = false;

  @override
  void initState() {
    super.initState();
    _controller = ValueNotifier<bool>(widget.value);
  }

  @override
  void didUpdateWidget(covariant _MasterSwitchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.value != widget.value) {
      _programmaticallyUpdating = true;
      _controller.value = widget.value;
      _programmaticallyUpdating = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.allowCustomSettings,
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          AdvancedSwitch(
            controller: _controller,
            activeColor: V2Theme.of(context).accent,
            inactiveColor: Color(0xFFE5E5E5),
            width: 50,
            height: 30,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
            onChanged: (v) {
              if (_programmaticallyUpdating) return;
              widget.onToggle(v as bool);
            },
          ),
        ],
      ),
    );
  }
}

class _RadioTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _RadioTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: V2Theme.of(context).textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 12),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? V2Theme.of(context).accent : V2Theme.of(context).textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MuteTile extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onToggle;
  const _MuteTile({required this.value, required this.onToggle});

  @override
  State<_MuteTile> createState() => _MuteTileState();
}

class _MuteTileState extends State<_MuteTile> {
  late final ValueNotifier<bool> _controller;

  /// 外部状态同步时赋值只更新显示，不触发 [onToggle]，避免 build 阶段
  /// （didUpdateWidget）回调里 setState 抛 "setState() called during build"。
  bool _programmaticallyUpdating = false;

  @override
  void initState() {
    super.initState();
    _controller = ValueNotifier<bool>(widget.value);
  }

  @override
  void didUpdateWidget(covariant _MuteTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.value != widget.value) {
      _programmaticallyUpdating = true;
      _controller.value = widget.value;
      _programmaticallyUpdating = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.mute,
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          AdvancedSwitch(
            controller: _controller,
            activeColor: V2Theme.of(context).accent,
            inactiveColor: Color(0xFFE5E5E5),
            width: 50,
            height: 30,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
            onChanged: (v) {
              if (_programmaticallyUpdating) return;
              widget.onToggle(v as bool);
            },
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: V2Theme.of(context).divider),
    );
  }
}
