import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pulsating_widget.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 应用内全屏来电页面（替代系统 CallKit/ConnectionService）。
///
/// 不使用系统通话界面，避免通话记录出现在系统电话列表中。
/// 限制：仅在 App 前台时可显示；后台/锁屏状态无推送时不提示来电。
class IncomingCallPage extends StatefulWidget {
  final Event event;
  const IncomingCallPage({super.key, required this.event});

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _onSync;
  Timer? _vibrationTimer;
  Timer? _timeoutTimer;

  /// 是否已执行过关闭。_close 可能被多个来源触发（拒绝按钮、onSync 检测到
  /// 主叫取消、超时），加幂等标志避免重复 pop 导致导航栈异常。
  bool _closed = false;

  Room get room => widget.event.room;

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _startVibration();
    _onSync = room.client.onSync.stream.listen((_) {
      if (!mounted) return;
      // 对方取消通话
      if (!room.hasActiveMatrixRtcCall) {
        Logs().i('Incoming call: caller cancelled');
        _close();
        return;
      }
      // 本端其他设备已接听
      final ownUserId = room.client.userID;
      final ownDeviceId = room.client.deviceID;
      if (ownUserId != null &&
          ownDeviceId != null &&
          room.getActiveMatrixRtcMembers().any(
            (member) =>
                member.senderId == ownUserId &&
                member.deviceId != ownDeviceId,
          )) {
        Logs().i('Incoming call: accepted on another device');
        _close();
      }
    });
    // 振铃有效期到了自动关闭
    final lifetime =
        widget.event.tryParseRtcNotificationContent()?.lifetime ??
        RtcNotificationContent.defaultLifetime;
    _timeoutTimer = Timer(lifetime, () {
      if (mounted) {
        Logs().i('Incoming call: timed out');
        _close();
      }
    });
  }

  Future<void> _initAudioPlayer() async {
    try {
      await _player.setAsset('assets/sounds/call_ring.mp3');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (e, s) {
      Logs().w('Unable to play incoming call ringtone', e, s);
    }
  }

  /// 每 2 秒振动一次，模拟来电振动
  void _startVibration() {
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _onSync?.cancel();
    _vibrationTimer?.cancel();
    _timeoutTimer?.cancel();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  /// 被叫方拒绝接听：发送拒绝通知给主叫方，然后关闭来电页。
  ///
  /// MatrixRTC 规范没有定义"拒绝"事件，这里用一个
  /// `org.matrix.msc4075.rtc.notification`（notification 类型）事件
  /// 携带 `m.call.reject: true` 自定义字段通知主叫方。主叫方收到后
  /// 立即结束呼叫，避免一直显示"呼叫中"。
  Future<void> _reject() async {
    if (!mounted) return;
    try {
      await room.sendCallRejectNotification();
    } catch (e, s) {
      Logs().w('Failed to send call reject notification', e, s);
    }
    if (mounted) _close();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    // 立即取消同步监听，避免主叫挂断后 onSync 再次触发 _close 导致重复 pop。
    _onSync?.cancel();
    _onSync = null;
    _vibrationTimer?.cancel();
    _timeoutTimer?.cancel();
    final navigator = Navigator.of(context);
    // 仅在可回退时 pop，防止来电页成为栈中唯一页面时触发 GoRouter
    // "popped the last page off of the stack" 断言。
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  void _accept() {
    final matrix = Matrix.of(context);
    // 被叫接听：CallViewModel 检测到房间已有活跃 MatrixRTC 通话会自动加入
    matrix.incomingCallRingEventId = widget.event.eventId;
    matrix.callPosition.value = CallPosition.fullScreen;
    matrix.activeCallRoomId.value = room.id;
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final displayname = room.getLocalizedDisplayname();
    final avatar = room.avatar;
    final intentStr = widget.event.content.tryGet<String>('m.call.intent');
    final isVideo =
        MatrixRtcCallIntent.values.singleWhereOrNull(
          (i) => i.name == intentStr,
        ) ==
        MatrixRtcCallIntent.video;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.92),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Text(
                isVideo ? l10n.videoCall : l10n.voiceCall,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              SizedBox(height: 24),
              PulsatingWidget(
                spreadRadius: 24.0,
                color: isVideo
                    ? theme.colorScheme.primary
                    : Colors.green.shade600,
                child: Avatar(
                  mxContent: avatar,
                  name: displayname,
                  size: 120,
                ),
              ),
              SizedBox(height: 24),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  displayname,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      label: l10n.reject,
                      color: Colors.red.shade700,
                      onPressed: _reject,
                    ),
                    _CallActionButton(
                      icon: isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      label: l10n.accept,
                      color: Colors.green.shade600,
                      onPressed: _accept,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: onPressed,
          radius: 36,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
