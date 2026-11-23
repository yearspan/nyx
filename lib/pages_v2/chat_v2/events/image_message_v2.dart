import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets_v2/upload_progress.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 图片/视频消息的裸内容（无气泡、无时间/状态），由 MessageBubbleV2 统一包裹
class ImageMessageV2 extends StatelessWidget {
  final Event event;
  final bool isMine;
  final bool isVideo;
  final VoidCallback? onTap;

  const ImageMessageV2({
    super.key,
    required this.event,
    required this.isMine,
    this.isVideo = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fileInfo = event.content.tryGetMap<String, Object?>('info');
    final w = fileInfo?.tryGet<int>('w');
    final h = fileInfo?.tryGet<int>('h');
    const maxSize = 220.0;

    var width = maxSize;
    var height = maxSize;
    if (w != null && h != null && w > 0 && h > 0) {
      if (w > h) {
        width = maxSize;
        height = maxSize * (h / w);
      } else {
        height = maxSize;
        width = maxSize * (w / h);
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: MxcImage(
                // 不能传 content['url']：加密房间该字段为 null（真实 mxc
                // 位于 content['file']['url']），传空 Uri 会在下载分支抛
                // "No host specified in URI"，导致解密分支永不执行、图片永久转圈。
                // 只传 event，由 MxcImage 的 downloadAndDecryptAttachment
                // 统一处理加密/明文（与原版 image_bubble.dart 一致）。
                key: ValueKey(event.eventId),
                cacheKey: event.transactionId ?? event.eventId,
                cacheName: event.room.id,
                event: event,
                width: width,
                height: height,
                fit: BoxFit.cover,
                animated: true,
              ),
            ),
            if (isVideo)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
              ),
            // 发送中遮罩：只显示进度转圈，不显示百分比数字
            if (event.status.isSending)
              Positioned.fill(
                child: Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: UploadProgressBuilder(
                    eventId: event.eventId,
                    builder: (context, progress) => SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.5,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
