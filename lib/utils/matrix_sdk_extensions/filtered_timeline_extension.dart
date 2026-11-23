import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

extension VisibleInGuiExtension on List<Event> {
  List<Event> filterByVisibleInGui({
    String? exceptionEventId,
    String? threadId,
  }) => where((event) {
    if (threadId != null &&
        event.relationshipType != RelationshipTypes.reaction) {
      if ((event.relationshipType != RelationshipTypes.thread ||
              event.relationshipEventId != threadId) &&
          event.eventId != threadId) {
        return false;
      }
    } else if (event.relationshipType == RelationshipTypes.thread) {
      return false;
    }
    return event.isVisibleInGui || event.eventId == exceptionEventId;
  }).toList();
}

extension IsStateExtension on Event {
  bool get isVisibleInGui =>
      // always filter out edit and reaction relationships
      !{
        RelationshipTypes.edit,
        RelationshipTypes.reaction,
      }.contains(relationshipType) &&
      // always filter out m.key.* and other known but unimportant events
      !isKnownHiddenStates &&

      !_isProfileChangeEvent &&
      // event types to hide: redaction and reaction events
      // if a reaction has been redacted we also want it to be hidden in the timeline
      !{EventTypes.Reaction, EventTypes.Redaction}.contains(type) &&
      // if we enabled to hide all redacted events, don't show those
      (!AppSettings.hideRedactedEvents.value || !redacted) &&
      // if we enabled to hide all unknown events, don't show those
      (!AppSettings.hideUnknownEvents.value ||
          isEventTypeKnown ||
          isKeyVerificationState);

  bool get _isProfileChangeEvent {
    if (type != EventTypes.RoomMember) return false;
    try {
      final changeType = roomMemberChangeType;
      return changeType == RoomMemberChangeType.avatar ||
          changeType == RoomMemberChangeType.displayname;
    }catch(e){
      return false;
    }
  }

  bool get isState => !{EventTypes.Message, EventTypes.Sticker}.contains(type);

  bool get isCollapsedState => !{
    EventTypes.Message,
    EventTypes.Sticker,
    EventTypes.RoomCreate,
    EventTypes.RoomTombstone,
  }.contains(type);

  /// 4 类对用户有意义的密钥验证状态消息
  static const Set<String> _visibleVerificationTypes = {
    EventTypes.KeyVerificationRequest,
    EventTypes.KeyVerificationReady,
    EventTypes.KeyVerificationDone,
    EventTypes.KeyVerificationCancel,
  };

  bool get isKeyVerificationState =>
      _visibleVerificationTypes.contains(type) ||
      // 未加密房间里请求以 m.room.message + 该 msgtype 的形式出现
      (type == EventTypes.Message &&
          messageType == EventTypes.KeyVerificationRequest);

  /// 需要在聊天时间线中隐藏的房间元数据状态事件
  /// （改名、改简介、改头像对用户无意义，不显示系统提示）
  static const Set<String> _hiddenRoomMetadataTypes = {
    EventTypes.RoomName,
    EventTypes.RoomTopic,
    EventTypes.RoomAvatar,
  };

  bool get isKnownHiddenStates =>
      {PollEventContent.responseType}.contains(type) ||
      _hiddenRoomMetadataTypes.contains(type) ||
      (type.startsWith('m.key.verification.') &&
          // 放行 4 类对用户有意义的验证状态消息：发起请求、接受、
          // 完成、取消；start/accept/key/mac 等协议内部事件继续隐藏
          !_visibleVerificationTypes.contains(type));
}
