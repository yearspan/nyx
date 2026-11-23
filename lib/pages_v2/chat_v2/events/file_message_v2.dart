import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_message_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/web_downloader.dart'
    if (dart.library.html) 'package:fluffychat/utils/web_downloader_web.dart';
import 'package:fluffychat/widgets_v2/upload_progress.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 文件消息（Telegram 风格）：
/// - 本地已缓存：显示文档图标，点击用系统应用打开
/// - 未缓存：显示下载图标，点击下载并显示转圈/进度
/// - 下载中：转圈 + 进度，叠加叉按钮可取消
class FileMessageV2 extends StatefulWidget {
  final Event event;
  final bool isMine;

  const FileMessageV2({super.key, required this.event, required this.isMine});

  @override
  State<FileMessageV2> createState() => _FileMessageV2State();
}

class _FileMessageV2State extends State<FileMessageV2> {
  late final ValueNotifier<DownloadState> _stateNotifier;

  @override
  void initState() {
    super.initState();
    _stateNotifier = FileMessageManager.getState(widget.event.eventId);
    _checkCache();
  }

  Future<void> _checkCache() async {
    // 已有明确状态（下载中/已缓存）则不覆盖
    if (_stateNotifier.value.status == DownloadStatus.downloading ||
        _stateNotifier.value.status == DownloadStatus.cached) {
      return;
    }
    final cached = await FileMessageManager.isCached(widget.event);
    if (!mounted) return;
    _stateNotifier.value = _stateNotifier.value.copyWith(
      status: cached ? DownloadStatus.cached : DownloadStatus.notCached,
    );
  }

  Future<void> _onTap() async {
    if (widget.event.status.isSending) return;
    final status = _stateNotifier.value.status;
    if (status == DownloadStatus.downloading) return;
    // l10n 提前捕获，避免跨异步间隙后 context 失效无法取文案
    final l10n = L10n.of(context);

    // web 端：尽量让浏览器直接下载（浏览器下载栏立即显示进度）
    if (PlatformInfos.isWeb) {
      _stateNotifier.value = _stateNotifier.value.copyWith(
        status: DownloadStatus.downloading,
        progress: 0,
      );
      try {
        final content = widget.event.content;
        final fileName =
            content.tryGet<String>('filename') ??
            content.tryGet<String>('body') ??
            L10n.of(context).unknownFile;
        // 未加密文件：取 mxc 的 HTTP 下载地址，交给浏览器直接下载
        final mxc = content.tryGet<String>('url');
        if (mxc != null && mxc.startsWith('mxc://')) {
          final uri = await Uri.parse(
            mxc,
          ).getDownloadUri(widget.event.room.client);
          if (uri.toString().isNotEmpty) {
            triggerBrowserDownload(uri, fileName);
            if (!mounted) return;
            _stateNotifier.value = _stateNotifier.value.copyWith(
              status: DownloadStatus.cached,
            );
            return;
          }
        }
        // 加密文件或无法直接下载：在内存解密后再保存
        final fileSize = widget.event.infoMap.tryGet<int>('size');
        final matrixFile = await widget.event.downloadAndDecryptAttachment(
          onDownloadProgress: fileSize == null
              ? null
              : (bytes) => _stateNotifier.value = _stateNotifier.value.copyWith(
                  progress: bytes / fileSize,
                ),
        );
        if (!mounted) return;
        await FilePicker.saveFile(
          dialogTitle: L10n.of(context).download,
          fileName: matrixFile.name,
          bytes: matrixFile.bytes,
        );
        if (!mounted) return;
        _stateNotifier.value = _stateNotifier.value.copyWith(
          status: DownloadStatus.cached,
        );
      } catch (_) {
        if (!mounted) return;
        _stateNotifier.value = _stateNotifier.value.copyWith(
          status: DownloadStatus.notCached,
        );
      }
      return;
    }

    // 已缓存：直接打开
    if (status == DownloadStatus.cached) {
      final path = await FileMessageManager.download(widget.event);
      if (!mounted) return;
      try {
        await FileMessageManager.open(path);
      } on OpenFileException {
        if (!mounted) return;
        // 如系统中没有可打开该类型的应用，避免表现为"点击没反应"
        V2Toast.show(l10n.couldNotOpenFile);
      }
      return;
    }

    // 未缓存：下载并打开（状态由 manager 内部设置，避免与"已在下载中"判断冲突）
    try {
      final path = await FileMessageManager.download(widget.event);
      if (!mounted) return;
      await FileMessageManager.open(path);
    } on OpenFileException {
      if (!mounted) return;
      // 下载已成功但系统无法打开（如没有支持该格式的应用）
      V2Toast.show(l10n.couldNotOpenFile);
    } catch (_) {
      // 取消或下载失败：状态已在 manager 中恢复为 notCached
    }
  }

  void _onCancel() {
    FileMessageManager.cancelDownload(widget.event.eventId);
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.event.content;
    // 文件名优先取 filename 字段；若 body 与 filename 不同，body 即为备注文本
    final fileName =
        content.tryGet<String>('filename') ??
        content.tryGet<String>('body') ??
        L10n.of(context).unknownFile;
    final body = content.tryGet<String>('body') ?? '';
    final caption = body.isNotEmpty && body != fileName ? body : null;
    final fileSize = _formatFileSize(
      content.tryGetMap<String, Object?>('info')?.tryGet<int>('size') ?? 0,
    );
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'FILE';
    final typeColor = widget.isMine ? Colors.white : _getTypeColor(extension);
    final nameColor = widget.isMine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final subColor = widget.isMine
        ? Colors.white70
        : V2Theme.of(context).textSecondary;

    return GestureDetector(
      onTap: _onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 左侧图标：根据状态显示文档图标 / 下载图标 / 转圈+取消
              SizedBox(width: 46, height: 46, child: _buildIcon(typeColor)),
              const SizedBox(width: 10),
              // 文件名 + 大小
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: nameColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileSize,
                      style: TextStyle(color: subColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 发送中：真实上传进度条 + 百分比（仅 macOS/iOS；其余平台不显示
          // 进度条，图标位的 UploadProgressCircle 会退化为不确定转圈）
          if (widget.event.status.isSending &&
              PlatformInfos.isMacOSOrIOS) ...[
            const SizedBox(height: 8),
            UploadProgressBuilder(
              eventId: widget.event.eventId,
              builder: (context, progress) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: subColor.withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(typeColor),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      uploadPercentLabel(progress),
                      style: TextStyle(color: subColor, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // 可选备注文本：显示在图标下方一行
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(caption, style: TextStyle(color: nameColor, fontSize: 14)),
          ],
        ],
      ),
    );
  }

  Widget _buildIcon(Color typeColor) {
    final isDesktop = !PlatformInfos.isMobile;
    // 发送中：显示真实上传进度的圆形指示器（无会话时内部回退为不确定转圈）
    if (widget.event.status.isSending) {
      return Center(
        child: UploadProgressCircle(
          eventId: widget.event.eventId,
          color: typeColor,
        ),
      );
    }
    return ValueListenableBuilder<DownloadState>(
      valueListenable: _stateNotifier,
      builder: (context, state, _) {
        switch (state.status) {
          case DownloadStatus.checking:
            if (isDesktop) {
              return CircleAvatar(
                radius: 23,
                backgroundColor: typeColor.withValues(alpha: 0.15),
                child: Icon(
                  Icons.description_outlined,
                  color: typeColor,
                  size: 26,
                ),
              );
            }
            // 手机端：检查中显示不确定转圈
            return Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(typeColor),
                ),
              ),
            );
          case DownloadStatus.downloading:
            // 下载中：显示带进度的转圈
            // 未加密文件叠加可点击的取消叉（可中断 HTTP 流）；
            // 加密文件走 SDK 下载不支持中途取消，不显示叉图标。
            final isEncrypted = widget.event.isAttachmentEncrypted;
            return Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    value: state.progress.clamp(0.0, 1.0),
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(typeColor),
                    backgroundColor: typeColor.withValues(alpha: 0.2),
                  ),
                ),
                if (!isEncrypted)
                  GestureDetector(
                    onTap: _onCancel,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Center(
                        child: Icon(Icons.close, color: typeColor, size: 18),
                      ),
                    ),
                  ),
              ],
            );
          case DownloadStatus.cached:
            // 已缓存：圆形文档图标
            return CircleAvatar(
              radius: 23,
              backgroundColor: typeColor.withValues(alpha: 0.15),
              child: Icon(
                Icons.description_outlined,
                color: typeColor,
                size: 26,
              ),
            );
          case DownloadStatus.notCached:
            // 未缓存：原版样式的圆形下载图标
            return CircleAvatar(
              radius: 23,
              backgroundColor: typeColor.withValues(alpha: 0.15),
              child: Icon(
                Icons.file_download_outlined,
                color: typeColor,
                size: 26,
              ),
            );
        }
      },
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Color _getTypeColor(String ext) {
    switch (ext) {
      case 'XLS':
      case 'XLSX':
      case 'CSV':
        return const Color(0xFF217346);
      case 'DOC':
      case 'DOCX':
        return const Color(0xFF2B579A);
      case 'PDF':
        return const Color(0xFFE53935);
      case 'ZIP':
      case 'RAR':
      case '7Z':
        return const Color(0xFFFF9800);
      case 'PPT':
      case 'PPTX':
        return const Color(0xFFE64A19);
      case 'TXT':
        return const Color(0xFF607D8B);
      case 'PNG':
      case 'JPG':
      case 'JPEG':
      case 'GIF':
      case 'WEBP':
        return const Color(0xFF8E24AA);
      default:
        return V2Theme.of(context).accent;
    }
  }
}
