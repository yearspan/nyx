import 'dart:ui';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

/// 通话期间的安卓前台服务。
///
/// 解决两类问题：
/// 1. Android 14+：后台（如锁屏接听来电）使用麦克风/摄像头必须持有
///    microphone/camera 类型的前台服务，否则采集被系统拒绝；
/// 2. 国产 ROM（MIUI/EMUI/ColorOS 等）的省电策略会限制后台 App
///    的网络（尤其 UDP），持有前台服务可提升进程与网络优先级，
///    对 WebRTC 的 ICE 保活至关重要。
///
/// 必须在 RECORD_AUDIO / CAMERA 运行时权限已授予后启动
/// （flutter_webrtc 创建音视频轨道时会触发申请）。
abstract class CallForegroundService {
  static const _channelId = 'fluffychat_call';
  static bool _started = false;

  /// [video] 为 true 时同时声明 camera 类型。
  static Future<void> start({required bool video}) async {
    if (!PlatformInfos.isAndroid || _started) return;
    try {
      final l10n = await L10n.delegate.load(
        PlatformDispatcher.instance.locale,
      );
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: _channelId,
          channelName: l10n.callNotificationsChannelName,
          channelDescription: l10n.callNotificationsChannelDescription,
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
        ),
      );

      if (await FlutterForegroundTask.isRunningService) {
        // 已有其它前台服务（如消息同步）在运行，不抢占也不负责停止它
        Logs().d('[CallFGS] Another foreground service is already running');
        return;
      }

      final result = await FlutterForegroundTask.startService(
        serviceTypes: [
          ForegroundServiceTypes.microphone,
          if (video) ForegroundServiceTypes.camera,
        ],
        notificationTitle: video ? l10n.videoCall : l10n.voiceCall,
        notificationText: l10n.callOngoingNotificationText,
        notificationIcon: const NotificationIcon(
          metaDataName: 'ic_launcher',
        ),
      );
      _started = result is ServiceRequestSuccess;
      Logs().d('[CallFGS] start: $_started ($result)');
    } catch (e, s) {
      // 后台启动被系统拒绝（如未授予权限/厂商策略）时不应中断通话
      Logs().w('[CallFGS] Unable to start call foreground service', e, s);
    }
  }

  static Future<void> stop() async {
    if (!PlatformInfos.isAndroid || !_started) return;
    _started = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e, s) {
      Logs().w('[CallFGS] Unable to stop call foreground service', e, s);
    }
  }
}
