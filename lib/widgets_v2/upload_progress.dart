import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:flutter/material.dart';

/// 监听待发送事件（eventId 即 txid）的上传进度并重建。
///
/// 平台策略：真实上传进度仅 macOS 与 iOS 展示；
/// Web / Android / Linux / Windows 不查询/不监听进度会话，[progress]
/// 恒为 null，调用方统一渲染不确定进度的转圈。
///
/// 不存在进度会话（非文件发送流程）或总大小未知时，[progress] 同样为
/// null，调用方应回退为不确定进度的转圈。
class UploadProgressBuilder extends StatelessWidget {
  final String eventId;
  final Widget Function(BuildContext context, double? progress) builder;

  const UploadProgressBuilder({
    super.key,
    required this.eventId,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    // 仅 macOS/iOS 展示真实进度：其余平台直接回退为不确定转圈，避免向
    // UploadProgressManager 注册监听。进度会话仍由发送链路正常维护，
    // 供取消按钮中止 HTTP 请求使用。
    if (!PlatformInfos.isMacOSOrIOS) return builder(context, null);
    final session = UploadProgressManager.instance.sessionFor(eventId);
    if (session == null) return builder(context, null);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => builder(context, session.progress),
    );
  }
}

/// 圆形上传进度指示器：有真实进度时显示确定值，否则显示不确定转圈。
///
/// 与下载进度（FileMessageV2 / VoiceMessageV2）的视觉风格保持一致，
/// 供文件、图片/视频、语音等所有文件类消息复用，避免各页面重复实现。
class UploadProgressCircle extends StatelessWidget {
  final String eventId;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color? trackColor;

  const UploadProgressCircle({
    super.key,
    required this.eventId,
    this.size = 30,
    this.strokeWidth = 2.5,
    required this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return UploadProgressBuilder(
      eventId: eventId,
      builder: (context, progress) {
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: progress?.clamp(0.0, 1.0),
            strokeWidth: strokeWidth,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            backgroundColor: trackColor ?? color.withValues(alpha: 0.2),
          ),
        );
      },
    );
  }
}

/// 百分比文案，进度未知时返回空串（不显示文本，仅保留转圈）。
String uploadPercentLabel(double? progress) {
  if (progress == null) return '';
  return '${(progress * 100).clamp(0, 100).round()}%';
}
