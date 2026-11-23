import 'dart:async';

import 'package:fluffychat/pages_v2/chat_v2/call/incoming_call_page.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/incoming_call_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 应用运行期间的来电监听器。
///
/// MatrixRTC 主叫在加入 LiveKit 之前会向 DM 房间发送一条
/// `org.matrix.msc4075.rtc.notification`（type=ring）事件，该事件随普通
/// /sync timeline 到达，不依赖系统推送通道（FCM/UnifiedPush）。
///
/// 原实现只在系统推送回调（push_helper）里弹 CallKit，未配置推送的设备
/// 即使 App 在前台也收不到任何来电提示。本监听器补齐前台链路，统一使用
/// 应用内来电界面，避免通话记录写入系统电话列表：
/// - 移动端：全屏 [IncomingCallPage]（铃声 + 振动 + 接听/拒绝）
/// - 桌面/Web：弹窗 [IncomingCallDialog]，接听后进入 V2 通话悬浮页
class IncomingCallWatcher {
  IncomingCallWatcher(this._matrix);

  final MatrixState _matrix;
  StreamSubscription? _subscription;

  /// 桌面端当前展示的来电弹窗所在房间，避免重复弹窗
  String? _dialogRoomId;

  /// 正在等待 context 就绪的重试计时器，dispose 时需取消
  Timer? _contextRetryTimer;

  void start() {
    if (_subscription != null) return;
    _subscription = _matrix.client.onTimelineEvent.stream.listen(
      _onTimelineEvent,
      onError: (Object e, StackTrace s) =>
          Logs().w('Incoming call watcher error', e, s),
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _contextRetryTimer?.cancel();
    _contextRetryTimer = null;
  }

  void _onTimelineEvent(Event event) {
    try {
      if (event.type != RtcNotificationContent.eventType) return;
      final content = event.tryParseRtcNotificationContent();
      if (content == null ||
          content.notificationType != RtcNotificationType.ring) {
        return;
      }

      final client = event.room.client;
      // 忽略自己其他设备发出的振铃
      if (event.senderId == client.userID) return;
      // ring 通知只在 lifetime（默认 30 秒）内有效
      if (content.senderTs
          .add(content.lifetime)
          .isBefore(DateTime.now())) {
        return;
      }

      final room = client.getRoomById(event.room.id);
      if (room == null || !room.isDirectChat) return;
      // 本设备已在该通话页中（含迷你窗）
      if (_matrix.activeCallRoomId.value == room.id) return;
      // 本设备已经加入该通话
      final ownUserId = client.userID;
      final ownDeviceId = client.deviceID;
      if (ownUserId != null &&
          room.getActiveMatrixRtcMembers().any(
            (member) =>
                member.senderId == ownUserId &&
                member.deviceId == ownDeviceId,
          )) {
        return;
      }

      if (PlatformInfos.isMobile) {
        _showInAppCallPage(event, room);
      } else {
        _showDesktopDialog(event, room);
      }
    } catch (e, s) {
      Logs().w('Unable to handle incoming call ring event', e, s);
    }
  }

  /// 获取当前导航 context。GoRouter 的 navigatorKey.currentContext 在 App
  /// 刚启动或路由切换瞬间可能为 null，此时延迟重试，最多等 3 秒，避免来电
  /// 事件到达但因 context 缺失而漏弹。
  BuildContext? _getNavigatorContext() {
    return FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
  }

  /// 移动端使用应用内全屏来电页。同一房间已有来电页时不重复弹出。
  void _showInAppCallPage(Event event, Room room) {
    if (_dialogRoomId != null) return;
    _dialogRoomId = room.id;

    void show() {
      final context = _getNavigatorContext();
      if (context == null) {
        // context 暂不可用，延迟 200ms 重试，最多 15 次（3 秒）
        _contextRetryTimer ??= Timer.periodic(
          const Duration(milliseconds: 200),
          (timer) {
            final ctx = _getNavigatorContext();
            if (ctx != null) {
              timer.cancel();
              _contextRetryTimer = null;
              _pushIncomingCallPage(ctx, event, room);
            } else if (timer.tick >= 15) {
              timer.cancel();
              _contextRetryTimer = null;
              _dialogRoomId = null;
              Logs().w(
                'Incoming call page not shown: navigator context unavailable '
                'after 3s retries, room=${room.id}',
              );
            }
          },
        );
        return;
      }
      _pushIncomingCallPage(context, event, room);
    }

    show();
  }

  void _pushIncomingCallPage(BuildContext context, Event event, Room room) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IncomingCallPage(event: event),
        ),
      ).then((_) {
        _dialogRoomId = null;
      }),
    );
  }

  void _showDesktopDialog(Event event, Room room) {
    if (_dialogRoomId != null) return; // 已有来电弹窗
    _dialogRoomId = room.id;

    void show() {
      final context = _getNavigatorContext();
      if (context == null) {
        _contextRetryTimer ??= Timer.periodic(
          const Duration(milliseconds: 200),
          (timer) {
            final ctx = _getNavigatorContext();
            if (ctx != null) {
              timer.cancel();
              _contextRetryTimer = null;
              _showDialog(ctx, event, room);
            } else if (timer.tick >= 15) {
              timer.cancel();
              _contextRetryTimer = null;
              _dialogRoomId = null;
              Logs().w(
                'Incoming call dialog not shown: navigator context '
                'unavailable after 3s retries, room=${room.id}',
              );
            }
          },
        );
        return;
      }
      _showDialog(context, event, room);
    }

    show();
  }

  void _showDialog(BuildContext context, Event event, Room room) {
    unawaited(
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => IncomingCallDialog(event: event),
      ).then((accepted) {
        _dialogRoomId = null;
        if (accepted == true) {
          // 被叫接听：CallViewModel 检测到房间已有活跃通话会自动加入
          _matrix.incomingCallRingEventId = event.eventId;
          _matrix.activeCallRoomId.value = room.id;
        }
      }),
    );
  }
}
