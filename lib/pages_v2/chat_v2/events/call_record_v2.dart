import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 通话记录的裸内容（图标+状态），气泡/时间/时长由 MessageBubbleV2 统一处理
class CallRecordV2 extends StatelessWidget {
  final Event event;

  const CallRecordV2({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final isMine = event.senderId == Matrix.of(context).client.userID;
    final textColor = isMine ? Colors.white : Theme.of(context).colorScheme.onSurface;

    // 解析 call event content
    final callContent = event.content.tryGetMap<String, Object?>('m.rtc.call') ??
        event.content.tryGetMap<String, Object?>('info');
    final callType = callContent?.tryGet<String>('type') ?? 'voice';
    final isVideo = callType == 'video';

    // 判断通话状态
    final isMissed = _isMissedCall(event, isMine);
    final isCanceled = _isCanceledCall(event);

    final l10n = L10n.of(context);
    String statusText;
    IconData icon;
    Color iconColor;

    if (isVideo) {
      icon = Icons.videocam;
      iconColor =
          isMissed ? Colors.red : (isCanceled ? Colors.grey : V2Theme.of(context).accent);
      if (isMissed) {
        // _isMissedCall 已保证仅接收方会命中
        statusText = l10n.missedVideoCall;
      } else if (isCanceled) {
        statusText = isMine
            ? l10n.videoCallCanceled
            : l10n.otherPartyCanceledVideoCall;
      } else {
        statusText = l10n.videoCall;
      }
    } else {
      icon = Icons.call;
      iconColor =
          isMissed ? Colors.red : (isCanceled ? Colors.grey : V2Theme.of(context).accent);
      if (isMissed) {
        statusText = l10n.missedCall;
      } else if (isCanceled) {
        statusText =
            isMine ? l10n.callCanceled : l10n.otherPartyCanceledCall;
      } else {
        statusText = isMine ? l10n.voiceCall : l10n.incomingCall;
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 20),
        SizedBox(width: 8),
        Text(
          statusText,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  bool _isMissedCall(Event event, bool isMine) {
    if (isMine) return false;
    const reason = 'm.call.missed';
    return event.content.tryGet<String>('reason') == reason;
  }

  bool _isCanceledCall(Event event) {
    const reason = 'm.call.cancel';
    return event.content.tryGet<String>('reason') == reason;
  }
}
