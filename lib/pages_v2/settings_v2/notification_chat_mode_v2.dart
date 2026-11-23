import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/settings_v2/notifications_v2.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// 聊天类型：群聊 / 私聊
enum NotificationChatType { group, private }

/// 群聊 / 私聊 通知模式选择页
class NotificationChatModeV2 extends StatefulWidget {
  final NotificationChatType type;
  const NotificationChatModeV2({super.key, required this.type});

  @override
  State<NotificationChatModeV2> createState() => _NotificationChatModeV2State();
}

class _NotificationChatModeV2State extends State<NotificationChatModeV2> {
  bool get isGroup => widget.type == NotificationChatType.group;

  Client get client => Matrix.of(context).client;

  NotificationMode get _currentMode {
    final rules = client.globalPushRules;
    if (rules == null) return NotificationMode.allMessages;
    final ids = isGroup
        ? const ['.m.rule.message', '.m.rule.encrypted']
        : const ['.m.rule.room_one_to_one', '.m.rule.encrypted_room_one_to_one'];
    final allEnabled = ids.every((id) {
      for (final r in rules.underride ?? const <PushRule>[]) {
        if (r.ruleId == id) return r.enabled;
      }
      return true;
    });
    return allEnabled
        ? NotificationMode.allMessages
        : NotificationMode.mentionsOnly;
  }

  Future<void> _setMode(NotificationMode mode) async {
    final enabled = mode == NotificationMode.allMessages;
    final ids = isGroup
        ? const ['.m.rule.message', '.m.rule.encrypted']
        : const ['.m.rule.room_one_to_one', '.m.rule.encrypted_room_one_to_one'];
    try {
      for (final id in ids) {
        await client.setPushRuleEnabled(PushRuleKind.underride, id, enabled);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toString());
    }
  }

  /// 有独立通知设置的群聊房间
  List<Room> get _independentRooms {
    if (!isGroup) return const [];
    final rules = client.globalPushRules;
    if (rules == null) return const [];
    final roomIds = <String>{
      ...?rules.room?.map((r) => r.ruleId),
      ...?rules.override
          ?.where((r) => !r.ruleId.startsWith('.m.'))
          .map((r) => r.ruleId),
    };
    if (roomIds.isEmpty) return const [];
    return client.rooms.where((r) => roomIds.contains(r.id)).toList();
  }

  String _stateLabel(BuildContext context, PushRuleState state) {
    final l10n = L10n.of(context);
    return switch (state) {
      PushRuleState.notify => l10n.notifyAll,
      PushRuleState.mentionsOnly => l10n.mentionsOnly,
      PushRuleState.dontNotify => l10n.mute,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final mode = _currentMode;
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: isGroup ? l10n.groupChat : l10n.privateChat),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: 12, bottom: 40),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    isGroup
                        ? l10n.notifyMeInGroupChats
                        : l10n.notifyMeInPrivateChats,
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
                        selected: mode == NotificationMode.allMessages,
                        onTap: () => _setMode(NotificationMode.allMessages),
                      ),
                      const _Divider(),
                      _RadioTile(
                        title: l10n.mentionsAndKeywords,
                        selected: mode == NotificationMode.mentionsOnly,
                        subtitle: l10n.mentionsAndKeywordsSubtitleGroup,
                        onTap: () => _setMode(NotificationMode.mentionsOnly),
                      ),
                    ],
                  ),
                ),
                if (isGroup && _independentRooms.isNotEmpty) ...[
                  SizedBox(height: 24),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      l10n.independentSettingsPerChat,
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
                        for (var i = 0; i < _independentRooms.length; i++) ...[
                          _RoomTile(
                            room: _independentRooms[i],
                            trailing: _stateLabel(
                                context, _independentRooms[i].pushRuleState),
                            onTap: () => context.push(
                              '/v2/notifications/room/${_independentRooms[i].id}',
                            ),
                          ),
                          if (i < _independentRooms.length - 1) const _Divider(),
                        ],
                      ],
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

class _RoomTile extends StatelessWidget {
  final Room room;
  final String trailing;
  final VoidCallback onTap;
  const _RoomTile({
    required this.room,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: V2Theme.of(context).accentLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.group_outlined,
                size: 20,
                color: V2Theme.of(context).accent,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                room.getLocalizedDisplayname(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
            Text(
              trailing,
              style: TextStyle(fontSize: 14, color: V2Theme.of(context).textSecondary),
            ),
            SizedBox(width: 4),
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: V2Theme.of(context).divider),
    );
  }
}
