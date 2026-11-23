import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/call/call_record_store.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// MatrixRTC 振铃事件（org.matrix.msc4075.rtc.notification）的通话记录气泡，
/// 微信样式：标题（拨出/来电/未接/已取消）+ 方向箭头、时间、时长 + 右侧大图标。
///
/// 通话结果不在房间历史里，由本设备在通话结束时写入 [CallRecordStore]；
/// 在振铃有效期（默认 30 秒）内显示「拨出/来电」，超时无记录则显示
/// 「通话已取消/未接电话」，记录写入后自动刷新并显示通话时长。
class RtcCallRecordV2 extends StatefulWidget {
  final Event event;

  const RtcCallRecordV2({super.key, required this.event});

  @override
  State<RtcCallRecordV2> createState() => _RtcCallRecordV2State();
}

class _RtcCallRecordV2State extends State<RtcCallRecordV2> {
  static const _wechatGreen = Color(0xFF07C160);
  static const _missedOnOther = Color(0xFFFA5151);
  static const _missedOnMine = Color(0xFFFFB3AC);

  /// 已取消：不用刺眼的红色，白色气泡上用柔和灰，
  /// 自己的青色气泡上用半透明白
  static const _canceledOnOther = Color(0xFFB3B3B3);
  static const _canceledOnMine = Color(0xffB8E7E4);

  Timer? _expiryTimer;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CallRecordStore.instance,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final event = widget.event;
    final l10n = L10n.of(context);
    final isMine = event.senderId == Matrix.of(context).client.userID;
    final record = CallRecordStore.instance.get(event.eventId);
    final rtc = event.tryParseRtcNotificationContent();
    final expiry = rtc == null
        ? null
        : rtc.getEffectiveTimestamp(event.originServerTs).add(
          rtc.cappedLifetime,
        );
    final now = DateTime.now();
    final expired = expiry == null || !expiry.isAfter(now);

    // 振铃中且本设备尚无记录：到 lifetime 时自动翻成「未接/已取消」
    if (!expired && record == null) {
      _expiryTimer ??= Timer(
        expiry.difference(now),
        () {
          if (mounted) setState(() {});
        },
      );
    }

    final isVideo =
        event.content.tryGet<String>('m.call.intent') ==
            MatrixRtcCallIntent.video.name ||
        (record?.isVideo ?? false);

    // 语气色调：未接电话用红色提醒，通话已取消用柔和中性灰，
    // 正常拨出/来电/接通跟随气泡（白气泡绿色、自己的气泡白色）
    final String title;
    final bool missed;
    final bool canceled;
    Duration? duration;
    if (record != null) {
      switch (record.outcome) {
        case CallRecordOutcome.answered:
          title = isMine ? l10n.callOutgoing : l10n.incomingCall;
          missed = false;
          canceled = false;
          duration = record.duration;
        case CallRecordOutcome.missed:
          title = l10n.missedCall;
          missed = true;
          canceled = false;
        case CallRecordOutcome.cancelled:
          title = l10n.callCanceled;
          missed = false;
          canceled = true;
      }
    } else if (expired) {
      // 本设备未参与的通话：主叫取消 / 被叫未接
      title = isMine ? l10n.callCanceled : l10n.missedCall;
      missed = !isMine;
      canceled = isMine;
    } else {
      // 正在振铃
      title = isMine ? l10n.callOutgoing : l10n.incomingCall;
      missed = false;
      canceled = false;
    }

    final titleColor = isMine ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final Color accentColor;
    if (missed) {
      accentColor = isMine ? _missedOnMine : _missedOnOther;
    } else if (canceled) {
      accentColor = isMine ? _canceledOnMine : _canceledOnOther;
    } else {
      accentColor = isMine ? Colors.white : _wechatGreen;
    }

    final timeText = DateFormat('HH:mm').format(event.originServerTs);
    final durationText = duration == null || duration.inSeconds < 1
        ? null
        : _formatDuration(l10n, duration);

    return SizedBox(
      width: 226,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                //SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      isMine
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      size: 15,
                      color: accentColor,
                    ),
                    SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        durationText == null
                            ? timeText
                            : '$timeText, $durationText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: accentColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Icon(
            isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            size: 34,
            // 已取消：图标也用柔和中性色；未接/正常保持绿色（自己的气泡白色）
            color: canceled || isMine ? accentColor : _wechatGreen,
          ),
        ],
      ),
    );
  }

  static String _formatDuration(L10n l10n, Duration d) {
    final seconds = d.inSeconds;
    if (seconds < 60) return l10n.callDurSeconds(seconds);
    final minutes = seconds ~/ 60;
    if (minutes < 60) return l10n.callDurMinutes(minutes);
    final hours = minutes ~/ 60;
    return l10n.callDurHourMinutes(hours, minutes % 60);
  }
}
