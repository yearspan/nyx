import 'package:fluffychat/l10n/l10n.dart';
import 'package:matrix/matrix.dart';

/// 将权限等级（整数）映射为三档显示文案
/// （仅限管理员 / 管理员和协管员 / 成员）
String levelToPermissionLabel(int level, L10n l10n) {
  if (level >= PowerLevel.defaultAdminLevel) return l10n.adminsOnly;
  if (level >= PowerLevel.defaultModeratorLevel) {
    return l10n.adminsAndModerators;
  }
  return l10n.members;
}

/// 将用户权限等级映射为角色名称（管理员 / 协管员 / 成员）
String levelToRoleLabel(int level, L10n l10n) {
  if (level >= PowerLevel.defaultAdminLevel) return l10n.admin;
  if (level >= PowerLevel.defaultModeratorLevel) return l10n.moderator;
  return l10n.members;
}

/// 对比 m.room.power_levels 事件的新旧内容，生成详细的变更说明。
///
/// 每条变更都是完整句子，直接包含操作者，形如：
/// ```
/// Alice 将邀请成员从成员改为管理员和协管员
/// Alice 将封禁成员从管理员和协管员改为成员
/// Alice 将 Bob 设为管理员
/// ```
///
/// 若无法解析出具体变更（如 prevContent 缺失），则回退为通用文案。
String buildPowerLevelsEventBody(Event event, L10n l10n) {
  final senderName = event.senderFromMemoryOrFallback.calcDisplayname();
  final newContent = event.content;
  final oldContent = event.prevContent;

  // 顶层权限字段 → 本地化名称
  final topLevelLabels = <String, String>{
    'invite': l10n.inviteMembers,
    'kick': l10n.removeMembers,
    'ban': l10n.banMembers,
    'redact': l10n.removeMessages,
    'events_default': l10n.sendMessages,
    'state_default': l10n.changeSettings,
  };

  // events 映射中的事件类型 → 本地化名称
  final eventLabels = <String, String>{
    EventTypes.RoomName: l10n.changeCommunityName,
    EventTypes.RoomAvatar: l10n.changeCommunityAvatar,
    EventTypes.RoomTopic: l10n.changeCommunityDescription,
  };

  final changes = <String>[];

  // 对比顶层字段
  for (final key in topLevelLabels.keys) {
    final oldLevel = oldContent?.tryGet<int>(key);
    final newLevel = newContent.tryGet<int>(key);
    if (newLevel != null && oldLevel != newLevel) {
      changes.add(
        l10n.permissionChangedFromTo(
          senderName,
          topLevelLabels[key]!,
          levelToPermissionLabel(oldLevel ?? 0, l10n),
          levelToPermissionLabel(newLevel, l10n),
        ),
      );
    }
  }

  // 对比 events 映射
  final oldEvents = oldContent?.tryGetMap<String, Object?>('events');
  final newEvents = newContent.tryGetMap<String, Object?>('events');
  for (final entry in eventLabels.entries) {
    final oldLevel = oldEvents?.tryGet<int>(entry.key);
    final newLevel = newEvents?.tryGet<int>(entry.key);
    if (newLevel != null && oldLevel != newLevel) {
      changes.add(
        l10n.permissionChangedFromTo(
          senderName,
          entry.value,
          levelToPermissionLabel(oldLevel ?? 0, l10n),
          levelToPermissionLabel(newLevel, l10n),
        ),
      );
    }
  }

  // 对比 users 映射（成员角色变更）
  final oldUsers = oldContent?.tryGetMap<String, Object?>('users');
  final newUsers = newContent.tryGetMap<String, Object?>('users');
  if (newUsers != null) {
    for (final entry in newUsers.entries) {
      final userId = entry.key;
      final newLevel = entry.value as int?;
      final oldLevel = oldUsers?.tryGet<int>(userId);
      if (newLevel != null && oldLevel != newLevel) {
        final targetName = event.room
            .unsafeGetUserFromMemoryOrFallback(userId)
            .calcDisplayname();
        changes.add(
          l10n.changedUserRoleTo(
            senderName,
            targetName,
            levelToRoleLabel(newLevel, l10n),
          ),
        );
      }
    }
  }

  if (changes.isEmpty) {
    return l10n.changedTheChatPermissions(senderName);
  }
  return changes.join('\n');
}
