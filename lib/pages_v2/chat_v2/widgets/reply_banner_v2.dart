import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Telegram 风格的回复预览横幅
///
/// 位于气泡内容上方，左侧一条竖向色条，右侧两行：
/// 第一行加粗显示被回复消息的发送者，第二行单行预览被回复的消息内容。
/// 被回复事件通过 [Event.getReplyEvent] 异步获取（可能从数据库加载），
/// 因此内部使用 FutureBuilder。
class ReplyBannerV2 extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final bool isMine;

  const ReplyBannerV2({
    super.key,
    required this.event,
    required this.timeline,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final replyId = event.inReplyToEventId(includingFallback: false);
    if (replyId == null) return SizedBox.shrink();

    final barColor = isMine ? Colors.white : V2Theme.of(context).accent;
    final nameColor = isMine ? Colors.white : V2Theme.of(context).accent;
    final previewColor = isMine
        ? Colors.white.withValues(alpha: 0.75)
        : V2Theme.of(context).textSecondary;

    return FutureBuilder<Event?>(
      future: event.getReplyEvent(timeline),
      builder: (context, snapshot) {
        final replyEvent = snapshot.data;
        final l10n = L10n.of(context);

        // 发送者名称
        final senderName = replyEvent?.senderFromMemoryOrFallback
                .calcDisplayname(i18n: MatrixLocals(l10n)) ??
            '...';

        // 被回复消息的预览文本
        final preview = _buildPreview(replyEvent, l10n);

        return Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧竖向色条
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: nameColor,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: previewColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 根据被回复消息的类型生成单行预览文本
  String _buildPreview(Event? replyEvent, L10n l10n) {
    if (replyEvent == null) return '...';

    // 非 m.room.message 类型（如状态事件），取本地化文案
    if (replyEvent.type != EventTypes.Message &&
        replyEvent.type != EventTypes.Sticker &&
        replyEvent.type != EventTypes.Encrypted) {
      return replyEvent
          .calcLocalizedBodyFallback(
            MatrixLocals(l10n),
            withSenderNamePrefix: false,
            hideReply: true,
          )
          .replaceAll('\n', ' ');
    }

    switch (replyEvent.messageType) {
      case MessageTypes.Image:
        return '📷 ${l10n.previewImage}';
      case MessageTypes.Video:
        return '🎬 ${l10n.previewVideo}';
      case MessageTypes.Audio:
        return '🎵 ${l10n.previewVoice}';
      case MessageTypes.File:
        return '📎 ${replyEvent.body}';
      case MessageTypes.Sticker:
        return l10n.previewSticker;
      case MessageTypes.Location:
        return '📍 ${l10n.previewLocation}';
      default:
        // 文本类：去掉回复 fallback 后取纯文本
        return replyEvent
            .calcLocalizedBodyFallback(
              MatrixLocals(l10n),
              withSenderNamePrefix: false,
              hideReply: true,
              plaintextBody: true,
            )
            .trim()
            .replaceAll('\n', ' ');
    }
  }
}
