import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/error_reporter.dart';
import '../../widgets/mxc_image.dart';

class EventVideoPlayer extends StatefulWidget {
  final Event event;

  /// 是否显示 Chewie 内置控制条。外部需要自定义控制条时传 false。
  final bool showControls;

  /// VideoPlayerController 就绪回调，供外部构建自定义控制条使用。
  final ValueChanged<VideoPlayerController>? onVideoPlayerControllerReady;

  const EventVideoPlayer(
    this.event, {
    super.key,
    this.showControls = true,
    this.onVideoPlayerControllerReady,
  });

  @override
  EventVideoPlayerState createState() => EventVideoPlayerState();
}

class EventVideoPlayerState extends State<EventVideoPlayer> {
  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;

  /// 下载进度 0~1；null 表示非网络下载阶段（本地读取/初始化），显示不确定进度
  double? _downloadProgress;

  /// 明文视频缓存文件路径。
  ///
  /// 路径只依赖 eventId 和附件文件名（均可在下载前从事件本身推导，
  /// SDK 返回的 MatrixFile.name 同样取自 `filename ?? body`），
  /// 因此无需先经过「读 SDK 数据库 + AES 解密」即可判断本地是否已缓存，
  /// 重复打开同一视频时可以直接初始化原生播放器实现秒开。
  Future<File> _getCacheFile() async {
    final tempDir = await getTemporaryDirectory();
    return File('${tempDir.path}/${widget.event.eventId}${_fileExtension()}');
  }

  /// 从事件的 filename/body 或 mimetype 推导视频文件扩展名
  String _fileExtension() {
    final name =
        widget.event.content.tryGet<String>('filename') ?? widget.event.body;
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      final ext = name.substring(dot + 1).toLowerCase();
      // 仅接受常见短扩展名，防止异常字符进入文件路径
      if (RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext)) return '.$ext';
    }
    switch (widget.event.attachmentMimetype) {
      case 'video/quicktime':
        return '.mov';
      case 'video/webm':
        return '.webm';
      case 'video/x-matroska':
        return '.mkv';
      case 'video/3gpp':
      case 'video/3gpp2':
        return '.3gp';
      default:
        return '.mp4';
    }
  }

  Future<void> _downloadAction() async {
    try {
      // 1) 最快路径：已解密的明文缓存文件存在，直接播放。
      //    不再调用 downloadAndDecryptAttachment，跳过读库与解密耗时。
      if (!kIsWeb) {
        final cacheFile = await _getCacheFile();
        if (await cacheFile.exists()) {
          await _startController(VideoPlayerController.file(cacheFile));
          return;
        }
      }

      // 2) 明文文件不存在：优先读 SDK 本地缓存（收到消息时可能已落库），
      //    读不到再走网络下载。
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      MatrixFile videoFile;
      try {
        videoFile = await widget.event.downloadAndDecryptAttachment(
          fromLocalStoreOnly: true,
        );
      } catch (_) {
        videoFile = await widget.event.downloadAndDecryptAttachment(
          onDownloadProgress: fileSize == null
              ? null
              : (received) {
                  if (!mounted) return;
                  final progress = received / fileSize;
                  setState(() {
                    _downloadProgress = progress < 1 ? progress : null;
                  });
                },
        );
      }

      _disposeControllers();
      late VideoPlayerController videoPlayerController;

      if (kIsWeb) {
        videoPlayerController = VideoPlayerController.networkUrl(
          Uri.dataFromBytes(videoFile.bytes, mimeType: videoFile.mimeType),
        );
      } else {
        final file = await _getCacheFile();
        if (!await file.exists()) {
          await file.writeAsBytes(videoFile.bytes, flush: true);
        }
        videoPlayerController = VideoPlayerController.file(file);
      }
      await _startController(videoPlayerController);
    } on IOException catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    } catch (e, s) {
      if (!mounted) return;
      ErrorReporter(context, 'Unable to play video').onErrorCallback(e, s);
    }
  }

  Future<void> _startController(VideoPlayerController controller) async {
    _videoPlayerController = controller;
    await controller.initialize();
    // 初始化期间页面可能已销毁
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _downloadProgress = null;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        showControlsOnInitialize: false,
        autoPlay: true,
        autoInitialize: true,
        looping: true,
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9,
        showControls: widget.showControls,
        showOptions: false,
        // 去掉静音、倍速按钮，保留进度条 + 全屏，控制条更简洁
        allowMuting: false,
        allowPlaybackSpeedChanging: false,
        // 进度条配色：已播放为 V2 强调色，缓冲/轨道为半透明白色，拖柄白色
        materialProgressColors: ChewieProgressColors(
          playedColor: V2Theme.of(context).accent,
          bufferedColor: Colors.white.withValues(alpha: 0.35),
          backgroundColor: Colors.white.withValues(alpha: 0.25),
          handleColor: Colors.white,
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: V2Theme.of(context).accent,
          bufferedColor: Colors.white.withValues(alpha: 0.35),
          backgroundColor: Colors.white.withValues(alpha: 0.25),
          handleColor: Colors.white,
        ),
      );
      widget.onVideoPlayerControllerReady?.call(controller);
    });
  }

  void _disposeControllers() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _chewieController = null;
    _videoPlayerController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 立即开始，不再等一帧；context 仅在 await 之后使用且有 mounted 保护
    _downloadAction();
  }

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = widget.event.hasThumbnail;
    final blurHash =
        (widget.event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final infoMap = widget.event.content.tryGetMap<String, Object?>('info');
    final videoWidth = infoMap?.tryGet<int>('w') ?? 0;
    final videoHeight = infoMap?.tryGet<int>('h') ?? 0;
    final screenSize = MediaQuery.sizeOf(context);
    final height = screenSize.height - 52;

    // 安全计算显示宽度：视频的 w/h 可能缺失或为 0（例如桌面端发出的视频
    // 未经 LightCompressor 解析尺寸），此时回退到 16:9 并限制不超过屏宽。
    final aspectRatio = (videoWidth > 0 && videoHeight > 0)
        ? videoWidth / videoHeight
        : 16 / 9;
    final width = (height * aspectRatio).clamp(0.0, screenSize.width);

    final chewieController = _chewieController;
    if (chewieController != null) {
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Theme(
            data: ThemeData(
              iconTheme: const IconThemeData(color: Colors.white, size: 26),
              textTheme: const TextTheme(
                bodySmall: TextStyle(color: Colors.white, fontSize: 12),
                labelSmall: TextStyle(color: Colors.white, fontSize: 12),
              ),
              sliderTheme: SliderThemeData(
                thumbColor: Colors.white,
                activeTrackColor: V2Theme.of(context).accent,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                overlayColor: V2Theme.of(
                  context,
                ).accent.withValues(alpha: 0.12),
                trackHeight: 2.5,
              ),
            ),
            child: Chewie(controller: chewieController),
          ),
        ),
      );
    }
    // 加载态：显示视频缩略图，中央只放一个 Telegram 风格的细圆环
    // （网络下载时展示真实进度，本地准备时为不确定动画），不放假播放按钮。
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Hero(
            tag: widget.event.eventId,
            child: hasThumbnail
                ? MxcImage(
                    event: widget.event,
                    isThumbnail: true,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    placeholder: (context) => BlurHash(
                      blurhash: blurHash,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                    ),
                  )
                : BlurHash(blurhash: blurHash, width: width, height: height),
          ),
        ),
        Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              value: _downloadProgress,
              strokeWidth: 2.5,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
