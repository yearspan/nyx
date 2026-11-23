import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:matrix/matrix.dart';

/// 仿照微信会话列表风格，把房间最后一条事件格式化成一行预览文案。
///
/// - 文本/通知/表情：显示正文（回复、编辑等交给 SDK 处理）
/// - 图片/视频/语音/文件/位置/贴纸：显示 `[类型]` 标签
/// - 通话：显示 `[语音通话]` / `[视频通话]`
/// - 群聊在前面加发送者前缀 `发送者: ...`，私聊不加
String formatLastEventPreview(Room room, L10n l10n) {
  final event = room.lastEvent;
  if (event == null) return '';

  // 撤回的事件：微信风格文案
  if (event.redacted) {
    final redactorId = event.redactedBecause?.senderId ?? event.senderId;
    final isMe = redactorId == room.client.userID;
    if (isMe) {
      return l10n.youWithdrewAMessage;
    }
    final redactorName = event.redactedBecause?.senderFromMemoryOrFallback
            .calcDisplayname(i18n: MatrixLocals(l10n)) ??
        event.senderFromMemoryOrFallback.calcDisplayname(
          i18n: MatrixLocals(l10n),
        );
    return l10n.userWithdrewAMessage(redactorName);
  }

  final isGroup = !room.isDirectChat;
  final type = event.type;

  // ---- MatrixRTC 通话 ----
  if (type == MatrixRtcCallMember.eventType) {
    return _withSenderPrefix(
      _callPreviewText(_resolveCallIntent(event), l10n),
      event,
      room,
      l10n,
    );
  }
  if (type == RtcNotificationContent.eventType) {
    final intentStr = event.content.tryGet<String>('m.call.intent');
    final intent =
        MatrixRtcCallIntent.values.firstWhereOrNull(
          (i) => i.name == intentStr,
        ) ??
        MatrixRtcCallIntent.video;
    return _withSenderPrefix(_callPreviewText(intent, l10n), event, room, l10n);
  }

  // ---- 旧版 VoIP 通话事件 ----
  if (type == EventTypes.CallInvite ||
      type == EventTypes.CallAnswer ||
      type == EventTypes.CallHangup ||
      type == EventTypes.CallReject) {
    // 旧版 m.call.invite 用 offer 里的 m=video 判断，没有则默认视频
    final offer = event.content.tryGetMap<String, Object?>('offer');
    final sdp = offer?.tryGet<String>('sdp') ?? '';
    final isVideo = sdp.contains('m=video');
    return _withSenderPrefix(
      isVideo ? l10n.previewVideoCall : l10n.previewVoiceCall,
      event,
      room,
      l10n,
    );
  }

  // ---- 普通消息 / 加密消息 ----
  if (type == EventTypes.Message || type == EventTypes.Encrypted) {
    switch (event.messageType) {
      case MessageTypes.Image:
        return _withSenderPrefix(l10n.previewImage, event, room, l10n);
      case MessageTypes.Video:
        return _withSenderPrefix(l10n.previewVideo, event, room, l10n);
      case MessageTypes.Audio:
        if (event.content.tryGetMap('org.matrix.msc3245.voice') != null) {
          return _withSenderPrefix(l10n.previewVoice, event, room, l10n);
        }
        return _withSenderPrefix(l10n.previewAudio, event, room, l10n);
      case MessageTypes.File:
        return _withSenderPrefix(l10n.previewFile, event, room, l10n);
      case MessageTypes.Location:
        return _withSenderPrefix(l10n.previewLocation, event, room, l10n);
      // 解密失败的消息在预览中留空，不展示原始异常或通用提示
      case MessageTypes.BadEncrypted:
        return '';
      case MessageTypes.Text:
      case MessageTypes.Notice:
      case MessageTypes.Emote:
      default:
        // 文本类交给 SDK，自动处理回复前缀剥离、编辑展示、发送者前缀
        return event.calcLocalizedBodyFallback(
          MatrixLocals(l10n),
          withSenderNamePrefix: isGroup,
          hideReply: true,
          plaintextBody: true,
          removeMarkdown: true,
        );
    }
  }

  // ---- 贴纸 ----
  if (type == EventTypes.Sticker) {
    return _withSenderPrefix(l10n.previewSticker, event, room, l10n);
  }

  // ---- 投票 ----
  if (type == PollEventContent.startType) {
    return _withSenderPrefix(l10n.poll, event, room, l10n);
  }

  // ---- 密钥验证状态消息（加密房间解密后的类型）----
  final matrixLocals = MatrixLocals(l10n);
  final senderName = event.senderFromMemoryOrFallback.calcDisplayname(
    i18n: matrixLocals,
  );
  switch (type) {
    case EventTypes.KeyVerificationRequest:
      return _withSenderPrefix(
        matrixLocals.requestedKeyVerification(senderName),
        event,
        room,
        l10n,
      );
    case EventTypes.KeyVerificationReady:
      return _withSenderPrefix(
        matrixLocals.isReadyForKeyVerification(senderName),
        event,
        room,
        l10n,
      );
    case EventTypes.KeyVerificationDone:
      return _withSenderPrefix(
        matrixLocals.completedKeyVerification(senderName),
        event,
        room,
        l10n,
      );
    case EventTypes.KeyVerificationCancel:
      return _withSenderPrefix(
        matrixLocals.canceledKeyVerification(senderName),
        event,
        room,
        l10n,
      );
  }

  // ---- 其它事件（房间状态变更、投票、反应等）交给 SDK 本地化 ----
  return event.calcLocalizedBodyFallback(
    MatrixLocals(l10n),
    withSenderNamePrefix: isGroup,
    hideReply: true,
    plaintextBody: true,
    removeMarkdown: true,
  );
}

/// 群聊加发送者前缀，私聊直接返回内容。
String _withSenderPrefix(String content, Event event, Room room, L10n l10n) {
  if (room.isDirectChat) return content;
  final sender = event.senderId == room.client.userID
      ? l10n.you
      : event.senderFromMemoryOrFallback.calcDisplayname(
          i18n: MatrixLocals(l10n),
        );
  return '$sender: $content';
}

String _callPreviewText(MatrixRtcCallIntent intent, L10n l10n) =>
    intent == MatrixRtcCallIntent.voice
    ? l10n.previewVoiceCall
    : l10n.previewVideoCall;

/// 从 call.member 事件解析通话意图。
///
/// 成员加入时 content 带 `m.call.intent`；离开时 content 为空 `{}`，
/// 此时回退到 prevContent 里的意图，否则默认视频。
MatrixRtcCallIntent _resolveCallIntent(Event event) {
  final intentStr =
      event.content.tryGet<String>('m.call.intent') ??
      event.prevContent?.tryGet<String>('m.call.intent');
  return MatrixRtcCallIntent.values.firstWhereOrNull(
        (i) => i.name == intentStr,
      ) ??
      MatrixRtcCallIntent.video;
}
