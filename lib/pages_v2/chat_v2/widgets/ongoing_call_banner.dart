import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 群聊顶部的「通话进行中 · N 人」横幅：
/// 群里有人开了通话而自己尚未加入时显示，点击直接加入。
/// 私聊是振铃模型，不显示此横幅。
class OngoingCallBanner extends StatefulWidget {
  final ChatV2Controller controller;

  const OngoingCallBanner({super.key, required this.controller});

  @override
  State<OngoingCallBanner> createState() => _OngoingCallBannerState();
}

class _OngoingCallBannerState extends State<OngoingCallBanner> {
  StreamSubscription<SyncUpdate>? _syncSub;

  /// 按「下一条 RTC 成员状态过期时间」安排一次重建，
  /// 让退出者（含把 App 直接滑掉的人）在过期后准点从人数中消失。
  Timer? _expiryTimer;

  Room get room => widget.controller.room;

  @override
  void initState() {
    super.initState();
    // 成员的 m.call.member 状态变化经 sync 到达，订阅后自动刷新横幅
    _syncSub = room.client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiryRebuild() {
    _expiryTimer?.cancel();
    final nextExpiry = room.nextMatrixRtcMembershipExpiry();
    if (nextExpiry == null) return;
    final delay = nextExpiry.difference(DateTime.now());
    if (!delay.isNegative && delay <= const Duration(minutes: 1)) {
      _expiryTimer = Timer(delay, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);

    // activeCallRoomId 变化（自己挂断退回聊天页）时重建横幅
    return ValueListenableBuilder<String?>(
      valueListenable: matrix.activeCallRoomId,
      builder: (context, activeCallRoomId, _) {
        if (room.isDirectChat) return SizedBox.shrink();
        if (!widget.controller.canCallInRoom) return SizedBox.shrink();
        // 自己已在通话中（全屏或迷你窗）不再提示加入
        if (activeCallRoomId == room.id) return SizedBox.shrink();
        if (room.ownMatrixRtcMembership != null) {
          _scheduleExpiryRebuild();
          return SizedBox.shrink();
        }
        if (!room.hasActiveMatrixRtcCall) {
          _scheduleExpiryRebuild();
          return SizedBox.shrink();
        }

        final memberCount = room.getActiveMatrixRtcMembers().length;
        final isVideo =
            room.activeMatrixRtcCallIntent == MatrixRtcCallIntent.video;

        _scheduleExpiryRebuild();

        return Material(
          color: V2Theme.of(context).accent.withValues(alpha: 0.10),
          child: InkWell(
            onTap: () => widget.controller.startCall(
              room.activeMatrixRtcCallIntent ?? MatrixRtcCallIntent.voice,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
              child: Row(
                children: [
                  Icon(
                    isVideo
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    size: 18,
                    color: V2Theme.of(context).accent,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${isVideo ? l10n.videoCall : l10n.voiceCall} · ${l10n.callParticipantsCount(memberCount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: V2Theme.of(context).accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      l10n.joinCall,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
