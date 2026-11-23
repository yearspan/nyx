import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/message_status_icon.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/translation_store.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class TextMessageV2 extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final bool showMeta; // 是否显示时间+已读标记
  final Color? textColor; // 文本颜色，不传时按发送者自动判断

  const TextMessageV2({
    super.key,
    required this.event,
    required this.timeline,
    this.showMeta = true,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = event.senderId == Matrix.of(context).client.userID;
    final color = textColor ?? (isMine ? Colors.white : Theme.of(context).colorScheme.onSurface);
    // 链接颜色：自己消息用白色（配 teal 气泡），对方消息用主题色
    final linkColor = isMine ? Colors.white : V2Theme.of(context).accent;

    // 编辑后的新内容在 m.replace 关系事件中，必须通过 getDisplayEvent
    // 取最新版本；时间与状态仍使用原事件。
    // 同时去掉回复 fallback（> <@user> 那几行），由 ReplyBannerV2 单独展示。
    final displayEvent = event.getDisplayEvent(timeline);
    final body = displayEvent.calcLocalizedBodyFallback(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix: false,
      hideReply: true,
    );

    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 文本内容（自动识别链接，点击跳转外部浏览器）
            Flexible(
              child: Linkify(
                text: body,
                options: const LinkifyOptions(humanize: false),
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  height: 1.4,
                ),
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize: 15,
                  height: 1.4,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              ),
            ),
            if (showMeta) ...[
              SizedBox(width: 8),
              // 时间 + 已读标记，跟在文本末尾同一行
              Text(
                _formatTime(event.originServerTs),
                style: TextStyle(
                  color: color.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
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
          ],
        ),
        // 翻译结果（微信风格：显示在原文下方，颜色更浅）
        ListenableBuilder(
          listenable: TranslationStore.instance.translatedEventIds,
          builder: (context, _) {
            final translated =
                TranslationStore.instance.getSync(event.eventId);
            if (translated == null || translated.isEmpty) {
              return SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                translated,
                style: TextStyle(
                  color: color.withValues(alpha: 0.55),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatTime(DateTime ts) {
    final time = ts.toLocal();
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
