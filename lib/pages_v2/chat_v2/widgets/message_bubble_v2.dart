import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/events/call_record_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/events/file_message_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/events/image_message_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/events/message_reactions_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/events/rtc_call_record_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/events/text_message_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/events/voice_message_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/chat_bubble_item.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/message_action_sheet.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/message_status_icon.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/reply_banner_v2.dart';
import 'package:fluffychat/pages_v2/image_viewer/image_viewer_v2.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/power_level_event_body.dart';
import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MessageBubbleV2 extends StatelessWidget {
  final Event event;

  /// 更新一条消息（视觉下方），用于头像/昵称分组
  final Event? nextEvent;

  /// 更老一条消息（视觉上方），用于判断日期分隔边界
  final Event? olderEvent;
  final bool isFirst;
  final Timeline timeline;
  final ChatV2Controller controller;

  const MessageBubbleV2({
    super.key,
    required this.event,
    required this.timeline,
    required this.controller,
    this.nextEvent,
    this.olderEvent,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    // 用户主动取消发送的占位事件：SDK 在 uploadContent 抛异常后会通过
    // fake sync 把它以 error 状态写回本地数据库，若不拦截会闪现一个
    // 错误气泡。命中取消集合直接不渲染，removeCancelledSendPlaceholder
    // 会随后从数据库清除它。
    if (UploadProgressManager.instance.isCancelledTxid(event.eventId)) {
      return const SizedBox.shrink();
    }

    // 无法解密的消息（m.bad.encrypted）以居中状态条展示，
    // 点击信息图标可查看原因并向发送方请求密钥。
    if (event.messageType == MessageTypes.BadEncrypted) {
      return _buildUnableToDecryptMessage(context);
    }

    // 除普通消息/贴纸/通话邀请外，其余事件（加入、离开、改名、
    // 非消息类事件（m.room.create、m.room.tombstone 等）按状态消息居中显示；
    // m.call.invite 与 MatrixRTC 振铃事件走通话记录气泡，
    // 其他 m.call.*（挂断、候选等）隐藏。
    // 投票开始事件走内容气泡渲染为投票卡片；投票响应/结束事件隐藏。
    if (event.type != EventTypes.Message &&
        event.type != EventTypes.Sticker &&
        event.type != EventTypes.CallInvite &&
        event.type != RtcNotificationContent.eventType &&
        event.type != PollEventContent.startType) {
      if (event.type.startsWith('m.call.')) {
        return SizedBox.shrink();
      }
      if (event.type == PollEventContent.responseType ||
          event.type == PollEventContent.endType) {
        return SizedBox.shrink();
      }
      return _buildStateMessage(context);
    }

    // 密钥验证请求（m.key.verification.request 等）以 m.room.message 形式
    // 出现，按状态消息居中渲染（如「XXX 发起了密钥验证」）
    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return _buildStateMessage(context);
    }

    final isMine = event.senderId == Matrix.of(context).client.userID;
    final room = event.room;
    final isDirectChat = room.isDirectChat;
    // 单聊不显示发送者昵称，群聊才显示
    final showSender = !isMine && !isDirectChat && _shouldShowSender();
    // 自己的消息不显示头像；私聊也不显示对方头像
    final showAvatar = !isMine && !isDirectChat && _shouldShowAvatar();
    final showTime = _shouldShowTime();

    final sender = event.senderFromMemoryOrFallback;
    final selecting = controller.isSelecting;
    final selected = controller.isEventSelected(event);
    final isHighlighted = controller.highlightEventId == event.eventId;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      color: isHighlighted
          ? V2Theme.of(context).accent.withValues(alpha: 0.14)
          : Colors.transparent,
      child: Opacity(
        opacity: selecting && !selected ? 0.5 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTime) _buildTimeDivider(context),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              // 多选模式下点击切换选中；普通模式不拦截内部点击
              // （图片预览、语音播放、文件下载等）
              onTap: selecting
                  ? () => controller.toggleSelectedEvent(event)
                  : null,
              onLongPressStart: (details) {
                if (selecting) {
                  controller.toggleSelectedEvent(event);
                } else {
                  HapticFeedback.mediumImpact();
                  MessageActionSheet.show(
                    context: context,
                    controller: controller,
                    event: event,
                    timeline: timeline,
                    anchor: details.globalPosition,
                  );
                }
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: isMine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  // 私聊整体不占头像位，消息贴左对齐；群聊保留头像槽位
                  if (!isMine && !isDirectChat) ...[
                    SizedBox(
                      width: 32,
                      child: showAvatar
                          ? Avatar(
                              mxContent: sender.avatarUrl,
                              name: sender.calcDisplayname(),
                              size: 32,
                            )
                          : null,
                    ),
                    SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (showSender)
                          Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 3),
                            child: Text(
                              sender.calcDisplayname(),
                              style: TextStyle(
                                fontSize: 12,
                                color: V2Theme.of(context).textSecondary,
                              ),
                            ),
                          ),
                        SizedBox(height: 6),
                        // 多选模式下吞掉气泡内部手势（播放/预览/下载），
                        // 外层 GestureDetector 仍正常响应以切换选中
                        AbsorbPointer(
                          absorbing: selecting,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _SendingCancelOverlay(
                                event: event,
                                child: _buildContentWithBubble(context, isMine),
                              ),
                              if (selected)
                                PositionedDirectional(
                                  top: -8,
                                  start: isMine ? null : -8,
                                  end: isMine ? -8 : null,
                                  child: Container(
                                    padding: EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: V2Theme.of(context).accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // 表情回应（无回应时组件自身返回 shrink）
                        MessageReactionsV2(event: event, timeline: timeline),
                      ],
                    ),
                  ),
                  // 右侧留白，保证自己的消息不会贴边（不再显示自己的头像）
                  if (isMine) SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentWithBubble(BuildContext context, bool isMine) {
    final backgroundColor = isMine
        ? V2Theme.of(context).accent
        : V2Theme.of(context).cardBackground;

    // 已撤回
    if (event.redacted) {
      return ChatBubbleItem(
        backgroundColor: backgroundColor,
        isMe: isMine,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReplyBannerV2(event: event, timeline: timeline, isMine: isMine),
            Text(
              L10n.of(context).messageDeleted,
              style: TextStyle(
                fontSize: 14,
                color: isMine
                    ? Colors.white.withValues(alpha: 0.7)
                    : V2Theme.of(context).textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    // 所有消息类型统一使用气泡+尾巴
    final textColor = isMine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final isMediaEvent =
        event.type == EventTypes.Message ||
        event.type == EventTypes.Encrypted ||
        event.type == EventTypes.Sticker;

    // 图片/视频：零内边距气泡；左上角视频时长、右下角时间+状态，
    // 均为半透明黑底药丸，保证在任意图片上可读
    if (isMediaEvent &&
        (event.messageType == MessageTypes.Image ||
            event.messageType == MessageTypes.Sticker ||
            event.messageType == MessageTypes.Video)) {
      final isVideo = event.messageType == MessageTypes.Video;
      final duration = isVideo ? _mediaDuration() : null;
      return ChatBubbleItem(
        backgroundColor: backgroundColor,
        isMe: isMine,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (event.inReplyToEventId(includingFallback: false) != null)
              Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: ReplyBannerV2(
                  event: event,
                  timeline: timeline,
                  isMine: isMine,
                ),
              ),
            Stack(
              children: [
                ImageMessageV2(
                  event: event,
                  isMine: isMine,
                  isVideo: isVideo,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => ImageViewerV2(
                        event,
                        timeline: timeline,
                        outerContext: context,
                      ),
                    ),
                  ),
                ),
                // 左上角：视频时长
                if (duration != null)
                  Positioned(
                    left: 8,
                    top: 6,
                    child: _overlayBadge(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, size: 12, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            duration,
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 右下角：时间 + 发送状态
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: _overlayBadge(child: _metaRow(isMine, Colors.white)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 语音：播放按钮+波形+时长同一行，右下角时间+状态
    if (isMediaEvent && event.messageType == MessageTypes.Audio) {
      return ChatBubbleItem(
        backgroundColor: backgroundColor,
        isMe: isMine,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ReplyBannerV2(event: event, timeline: timeline, isMine: isMine),
              VoiceMessageV2(event: event, isMine: isMine),
              SizedBox(height: 6),
              _metaRow(isMine, textColor),
            ],
          ),
        ),
      );
    }

    // 文件：图标+文件名，下方时间+状态
    if (isMediaEvent && event.messageType == MessageTypes.File) {
      return ChatBubbleItem(
        backgroundColor: backgroundColor,
        isMe: isMine,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReplyBannerV2(event: event, timeline: timeline, isMine: isMine),
              FileMessageV2(event: event, isMine: isMine),
              SizedBox(height: 6),
              _metaRow(isMine, textColor),
            ],
          ),
        ),
      );
    }

    // 通话记录：图标+状态，下方时间+通话时长+状态
    if (event.type == EventTypes.CallInvite) {
      return ChatBubbleItem(
        backgroundColor: backgroundColor,
        isMe: isMine,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReplyBannerV2(event: event, timeline: timeline, isMine: isMine),
              CallRecordV2(event: event),
              SizedBox(height: 6),
              _metaRow(isMine, textColor, duration: _callDuration()),
            ],
          ),
        ),
      );
    }

    // MatrixRTC 通话记录（微信样式，时间/时长已在气泡内）
    if (event.type == RtcNotificationContent.eventType) {
      return ChatBubbleItem(
        backgroundColor: backgroundColor,
        isMe: isMine,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReplyBannerV2(event: event, timeline: timeline, isMine: isMine),
            RtcCallRecordV2(event: event),
          ],
        ),
      );
    }

    // 文本/其他：时间显示在文本后面
    return ChatBubbleItem(
      backgroundColor: backgroundColor,
      isMe: isMine,
      showTail: true,
      child: DefaultTextStyle(
        style: TextStyle(color: textColor, fontSize: 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReplyBannerV2(event: event, timeline: timeline, isMine: isMine),
            _buildTextContent(context, isMine),
          ],
        ),
      ),
    );
  }

  /// 图片/视频浮层上的半透明黑底药丸（时间、时长、状态），
  /// 白色内容在任意图片上都可辨识
  Widget _overlayBadge({required Widget child}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  /// 气泡底部/角标元信息行：时间 + 时长（音视频/通话）+ 发送状态
  Widget _metaRow(bool isMine, Color color, {String? duration}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatHM(event.originServerTs),
            style: TextStyle(
              color: color.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
          if (duration != null) ...[
            SizedBox(width: 6),
            Text(
              duration,
              style: TextStyle(
                color: color.withValues(alpha: 0.75),
                fontSize: 11,
              ),
            ),
          ],
          if (isMine) ...[
            SizedBox(width: 4),
            MessageStatusIcon(
              event: event,
              timeline: timeline,
              size: 14,
              color: color.withValues(alpha: 0.9),
            ),
          ],
        ],
      ),
    );
  }

  /// 图片/视频/语音时长（毫秒 → mm:ss），无数据返回 null
  String? _mediaDuration() {
    final info = event.content.tryGetMap<String, Object?>('info');
    var ms = info?.tryGet<int>('duration') ?? 0;
    if (ms <= 0) {
      ms =
          event.content
              .tryGetMap<String, Object?>('org.matrix.msc1767.audio')
              ?.tryGet<int>('duration') ??
          0;
    }
    if (ms <= 0) return null;
    final totalSeconds = (ms / 1000).round();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 通话时长（秒 → mm:ss），无数据返回 null
  String? _callDuration() {
    final seconds = event.content.tryGet<int>('duration') ?? 0;
    if (seconds <= 0) return null;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  String _formatHM(DateTime ts) {
    final time = ts.toLocal();
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTextContent(BuildContext context, bool isMine) {
    switch (event.type) {
      case EventTypes.Message:
      case EventTypes.Encrypted:
      case EventTypes.Sticker:
        switch (event.messageType) {
          case MessageTypes.Text:
          case MessageTypes.Notice:
          case MessageTypes.Emote:
          case MessageTypes.None:
          default:
            return TextMessageV2(event: event, timeline: timeline);
        }
      case PollEventContent.startType:
        return _buildPollPreview(context, isMine);
      default:
        return TextMessageV2(event: event, timeline: timeline);
    }
  }

  /// 投票消息预览：展示问题和带单选按钮的选项，点击选项直接投票，
  /// 点击其他区域跳转到投票详情页
  Widget _buildPollPreview(BuildContext context, bool isMine) {
    final l10n = L10n.of(context);
    PollEventContent? content;
    try {
      content = event.parsedPollEventContent;
    } catch (_) {
      content = null;
    }
    final question = content?.pollStartContent.question.mText ?? '';
    final answers = content?.pollStartContent.answers ?? const [];
    final ended = event.getPollHasBeenEnded(timeline);

    // 当前用户已投的选项
    final myUserId = Matrix.of(context).client.userID ?? '';
    final myVotes =
        event.getPollResponses(timeline)[myUserId] ?? const <String>{};

    final primaryColor = isMine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final secondaryColor = isMine
        ? Colors.white.withValues(alpha: 0.7)
        : V2Theme.of(context).textSecondary;
    final accentColor = isMine ? Colors.white : V2Theme.of(context).accent;

    Future<void> vote(String answerId) async {
      try {
        await event.answerPoll([answerId]);
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.poll_outlined, size: 16, color: accentColor),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                question,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        for (final a in answers.take(4))
          Padding(
            padding: EdgeInsets.only(bottom: 7),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: ended ? null : () => vote(a.id),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    myVotes.contains(a.id)
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 17,
                    color: myVotes.contains(a.id)
                        ? accentColor
                        : secondaryColor,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      a.mText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: myVotes.contains(a.id)
                            ? primaryColor
                            : secondaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (answers.length > 4)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '+${answers.length - 4} ${l10n.more}',
              style: TextStyle(fontSize: 12, color: secondaryColor),
            ),
          ),
        SizedBox(height: 4),
        Text(
          ended ? l10n.pollHasBeenEnded : l10n.poll,
          style: TextStyle(fontSize: 12, color: secondaryColor),
        ),
      ],
    );
  }

  /// 密钥验证状态消息的本地化文案；非验证事件返回 null
  String? _calcVerificationBody(MatrixLocals matrixLocals) {
    final senderName = event.senderFromMemoryOrFallback.calcDisplayname(
      i18n: matrixLocals,
    );
    switch (event.type) {
      case EventTypes.KeyVerificationRequest:
        // 未加密房间里请求以 m.room.message + m.key.verification.request
        // 的形式出现，这里统一处理
        return matrixLocals.requestedKeyVerification(senderName);
      case EventTypes.KeyVerificationReady:
        return matrixLocals.isReadyForKeyVerification(senderName);
      case EventTypes.KeyVerificationDone:
        return matrixLocals.completedKeyVerification(senderName);
      case EventTypes.KeyVerificationCancel:
        return matrixLocals.canceledKeyVerification(senderName);
      default:
        return null;
    }
  }

  /// 无法解密的消息：按发送者方向左右对齐的灰色胶囊，
  /// 显示发送者头像 + 「消息不可解密」。
  Widget _buildUnableToDecryptMessage(BuildContext context) {
    final l10n = L10n.of(context);
    final isMine = event.senderId == Matrix.of(context).client.userID;
    final sender = event.senderFromMemoryOrFallback;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: V2Theme.of(context).divider.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(
              name: sender.calcDisplayname(),
              mxContent: sender.avatarUrl,
              size: 14,
            ),
            SizedBox(width: 6),
            Text(
              l10n.messageNotDecryptable,
              style: TextStyle(
                fontSize: 12,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateMessage(BuildContext context) {
    final l10n = L10n.of(context);
    final matrixLocals = MatrixLocals(l10n);
    // 密钥验证的 4 类状态消息在 SDK 的 localizationsMap 中未注册，
    // 直接走 calcLocalizedBodyFallback 会显示 unknown event，这里手动取文案
    final verificationBody = _calcVerificationBody(matrixLocals);
    var body =
        verificationBody ??
        (event.type == EventTypes.RoomPowerLevels
            ? buildPowerLevelsEventBody(event, l10n)
            : event.calcLocalizedBodyFallback(
                matrixLocals,
                withSenderNamePrefix: true,
                hideReply: true,
              ));
    // 自己触发的状态事件（创建聊天、改名、加入等），
    // 把文案中的自己昵称替换为「我」/「You」
    if (event.senderId == event.room.client.userID) {
      final ownName = event.senderFromMemoryOrFallback.calcDisplayname(
        i18n: matrixLocals,
      );
      if (ownName.isNotEmpty && body.contains(ownName)) {
        body = body.replaceAll(ownName, l10n.stateEventYou);
      }
    }
    // ListView 会给子项紧宽度约束，必须用 Center 包一层，
    // 否则背景条会拉满整行宽度。
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: V2Theme.of(context).divider.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeDivider(BuildContext context) {
    final l10n = L10n.of(context);
    final time = event.originServerTs.toLocal();
    final now = DateTime.now();
    String timeText;

    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      timeText = l10n.today;
    } else if (time.year == yesterday.year &&
        time.month == yesterday.month &&
        time.day == yesterday.day) {
      timeText = l10n.yesterday;
    } else if (time.year == now.year) {
      timeText = '${time.month}/${time.day}';
    } else {
      timeText = '${time.year}/${time.month}/${time.day}';
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 0.5, color: V2Theme.of(context).divider),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              timeText,
              style: TextStyle(
                fontSize: 12,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Container(height: 0.5, color: V2Theme.of(context).divider),
          ),
        ],
      ),
    );
  }

  // nextEvent 在反转列表中是「更新的一条」（显示在下方）
  bool _shouldShowAvatar() {
    if (nextEvent == null) return true;
    if (nextEvent!.senderId != event.senderId) return true;
    return nextEvent!.originServerTs.difference(event.originServerTs) >
        const Duration(minutes: 5);
  }

  /// 本条消息是其所在日期分组的第一条（视觉最上方）时显示分隔，
  /// 标签取本条消息的日期：
  /// - 它是当前加载的最老一条（上方无消息）：显示
  /// - 它与视觉上方更老的一条不在同一天：显示（如新一天的第一条）
  bool _shouldShowTime() {
    if (isFirst) return true;
    if (olderEvent == null) return false;
    final a = event.originServerTs.toLocal();
    final b = olderEvent!.originServerTs.toLocal();
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  bool _shouldShowSender() {
    if (nextEvent == null) return true;
    return nextEvent!.senderId != event.senderId;
  }
}

/// 发送中消息的取消按钮覆盖层。
///
/// - 桌面 / web：鼠标 hover 时在气泡右上角显示 ✕
/// - 手机端：始终显示 ✕（无 hover）
/// 点击时先通过上传进度会话中断进行中的 HTTP 请求（SDK 的
/// `cancelSend` 只删除本地占位事件，不会停止上传），再调用
/// `event.cancelSend()` 移除占位事件，双管齐下保证消息不会发出。
class _SendingCancelOverlay extends StatefulWidget {
  final Event event;
  final Widget child;

  const _SendingCancelOverlay({required this.event, required this.child});

  @override
  State<_SendingCancelOverlay> createState() => _SendingCancelOverlayState();
}

class _SendingCancelOverlayState extends State<_SendingCancelOverlay> {
  bool _hovering = false;

  /// 取消发送：先中断 HTTP 上传（含后续的事件提交请求），再移除本地
  /// 占位事件。占位事件的 eventId 即发送时注册的 txid。
  Future<void> _cancelSend() async {
    UploadProgressManager.instance.sessionFor(widget.event.eventId)?.cancel();
    try {
      await widget.event.cancelSend();
    } catch (_) {
      // 事件可能已被同步结果替换，取消失败不影响 HTTP 层中止。
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSending = widget.event.status == EventStatus.sending;
    // 仅发送文件类消息（图片/视频/音频/文件/贴纸）时才显示取消按钮，
    // 文本等纯消息不显示。
    final isFileMessage = const [
      MessageTypes.Image,
      MessageTypes.Video,
      MessageTypes.Audio,
      MessageTypes.File,
      MessageTypes.Sticker,
    ].contains(widget.event.messageType);
    // 手机端常显，桌面端 hover 显
    final showCancel =
        isSending && isFileMessage && (PlatformInfos.isMobile || _hovering);

    return MouseRegion(
      onEnter: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (showCancel)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelSend,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
