import 'dart:async';

import 'package:fluffychat/pages_v2/settings_v2/notifications_v2_view.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 通知模式：全部消息 / 仅提及和关键词
enum NotificationMode { allMessages, mentionsOnly }

/// V2 通知设置页（Page）
class NotificationsV2 extends StatefulWidget {
  const NotificationsV2({super.key});

  @override
  NotificationsV2Controller createState() => NotificationsV2Controller();
}

class NotificationsV2Controller extends State<NotificationsV2> {
  bool isLoading = false;
  StreamSubscription? _onSyncUpdate;

  Client get client => Matrix.of(context).client;

  PushRuleSet? get pushRules => client.globalPushRules;

  @override
  void initState() {
    super.initState();
    _onSyncUpdate = client.onSync.stream
        .where(
          (sync) =>
              sync.accountData
                  ?.any((a) => a.type == EventTypes.PushRules) ??
              false,
        )
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _onSyncUpdate?.cancel();
    super.dispose();
  }

  // ====== 总开关（在此设备上通知我）======
  bool get masterEnabled => !client.allPushNotificationsMuted;

  Future<void> toggleMaster(bool value) =>
      _withLoading(() => client.setMuteAllPushNotifications(!value));

  // ====== 群聊 / 私聊通知模式 ======
  /// 群聊：全部消息 = `.m.rule.message` 与 `.m.rule.encrypted` 均启用
  static const _groupMessageRule = '.m.rule.message';
  static const _groupEncryptedRule = '.m.rule.encrypted';

  /// 私聊：全部消息 = `.m.rule.room_one_to_one` 与
  /// `.m.rule.encrypted_room_one_to_one` 均启用
  static const _privateMessageRule = '.m.rule.room_one_to_one';
  static const _privateEncryptedRule = '.m.rule.encrypted_room_one_to_one';

  NotificationMode get groupChatMode => _modeOfRules(
        [_groupMessageRule, _groupEncryptedRule],
      );

  NotificationMode get privateChatMode => _modeOfRules(
        [_privateMessageRule, _privateEncryptedRule],
      );

  Future<void> setGroupChatMode(NotificationMode mode) =>
      _setMode([_groupMessageRule, _groupEncryptedRule], mode);

  Future<void> setPrivateChatMode(NotificationMode mode) =>
      _setMode([_privateMessageRule, _privateEncryptedRule], mode);

  // ====== 提及通知（群聊@时通知我）======
  static const _mentionRuleIds = [
    '.m.rule.is_user_mention',
    '.m.rule.is_room_mention',
    '.m.rule.contains_display_name',
    '.m.rule.contains_user_name',
  ];

  /// 只要任一提及规则启用，则视为开启
  bool get mentionEnabled => _mentionRuleIds
      .any((id) => _findRule(PushRuleKind.override, id)?.enabled ?? false);

  Future<void> toggleMention(bool value) => _withLoading(() async {
        for (final id in _mentionRuleIds) {
          await client.setPushRuleEnabled(PushRuleKind.override, id, value);
        }
      });

  // ====== 邀请通知 ======
  static const _inviteRuleId = '.m.rule.invite_for_me';

  bool get inviteEnabled =>
      _findRule(PushRuleKind.override, _inviteRuleId)?.enabled ?? true;

  Future<void> toggleInvite(bool value) => _withLoading(
        () => client.setPushRuleEnabled(
          PushRuleKind.override,
          _inviteRuleId,
          value,
        ),
      );

  // ====== 各群聊的独立设置 ======
  /// 有独立通知规则的房间列表
  List<Room> get roomsWithIndependentSettings {
    final rules = pushRules;
    if (rules == null) return const [];
    final roomIds = <String>{
      ...?rules.room?.map((r) => r.ruleId),
      // override 里以房间 ID 命名（非 .m. 开头）的规则表示该房间被静音
      ...?rules.override
          ?.where((r) => !r.ruleId.startsWith('.m.'))
          .map((r) => r.ruleId),
    };
    if (roomIds.isEmpty) return const [];
    return client.rooms.where((r) => roomIds.contains(r.id)).toList();
  }

  // ====== 工具方法 ======
  PushRule? _findRule(PushRuleKind kind, String ruleId) {
    final rules = switch (kind) {
      PushRuleKind.override => pushRules?.override,
      PushRuleKind.content => pushRules?.content,
      PushRuleKind.room => pushRules?.room,
      PushRuleKind.sender => pushRules?.sender,
      PushRuleKind.underride => pushRules?.underride,
    };
    for (final r in rules ?? const <PushRule>[]) {
      if (r.ruleId == ruleId) return r;
    }
    return null;
  }

  NotificationMode _modeOfRules(List<String> ruleIds) {
    final allEnabled = ruleIds.every(
      (id) => _findRule(PushRuleKind.underride, id)?.enabled ?? true,
    );
    return allEnabled
        ? NotificationMode.allMessages
        : NotificationMode.mentionsOnly;
  }

  Future<void> _setMode(List<String> ruleIds, NotificationMode mode) async {
    final enabled = mode == NotificationMode.allMessages;
    await _withLoading(() async {
      for (final id in ruleIds) {
        await client.setPushRuleEnabled(PushRuleKind.underride, id, enabled);
      }
    });
  }

  Future<void> _withLoading(Future<void> Function() fn) async {
    setState(() => isLoading = true);
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => NotificationsV2View(this);
}
