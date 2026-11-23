import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/mxc_image_disk_cache.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final String? cacheName;
  final Client? client;
  final BorderRadius borderRadius;

  static void clearCache(String cacheName) =>
      _MxcImageState._imageDataCaches.remove(cacheName);

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = FluffyThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = FluffyThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    this.borderRadius = BorderRadius.zero,
    this.cacheName,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  static final Map<String?, Map<String, Uint8List>> _imageDataCaches = {};
  Map<String, Uint8List> get _imageDataCache =>
      _imageDataCaches[widget.cacheName ?? ''] ??= {};

  Uint8List? _imageDataNoCache;

  Uint8List? get _imageData => widget.cacheKey == null
      ? _imageDataNoCache
      : _imageDataCache[widget.cacheKey];

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    cacheKey == null
        ? _imageDataNoCache = data
        : _imageDataCache[cacheKey] = data;
  }

  /// 磁盘缓存使用的 key（cacheKey > eventId > uri > 'img'）
  String get _cacheRawKey =>
      widget.cacheKey ??
      widget.event?.eventId ??
      widget.uri?.toString() ??
      'img';

  /// 仅 uri 场景（如头像）需要按尺寸区分缓存，避免不同尺寸互相覆盖
  bool get _includeSizeInCache => widget.uri != null;

  Future<void> _load() async {
    if (!mounted) return;

    // 先捕获所有依赖 context 的值，避免异步间隙后使用已失效的 context
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final width = widget.width;
    final realWidth = width == null ? null : width * devicePixelRatio;
    final height = widget.height;
    final realHeight = height == null ? null : height * devicePixelRatio;
    final uri = widget.uri;
    final event = widget.event;

    // 1) 最快路径：明文磁盘缓存命中则直接读取，跳过 SDK 读库 + 解密
    try {
      final cached = await MxcImageDiskCache.read(
        rawKey: _cacheRawKey,
        isThumbnail: widget.isThumbnail,
        includeSize: _includeSizeInCache,
        width: widget.width,
        height: widget.height,
      );
      if (cached != null) {
        if (!mounted) return;
        setState(() => _imageData = cached);
        return;
      }
    } catch (_) {
      // 磁盘缓存读取失败，继续走 SDK 流程
    }

    if (uri != null) {
      final remoteData = await client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: widget.isThumbnail,
        animated: widget.animated,
      );
      if (!mounted) return;
      setState(() {
        _imageData = remoteData;
      });
      _persistDiskCache(remoteData);
    }

    if (event != null) {
      final useThumbnail = widget.isThumbnail && event.hasThumbnail;
      if (!useThumbnail &&
          !{
            MessageTypes.Image,
            MessageTypes.Sticker,
          }.contains(event.messageType)) {
        Logs().e('Event of type ${event.messageType} has no thumbnail!');
      }
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: useThumbnail,
      );
      if (data.detectFileType is MatrixImageFile) {
        if (!mounted) return;
        setState(() {
          _imageData = data.bytes;
        });
        _persistDiskCache(data.bytes);
        return;
      }
      // 下载回来的内容不是图片（例如视频事件缺缩略图时会下载整个视频），
      // MxcImage 无法渲染，记录实际类型便于定位"缩略图空白"问题。
      Logs().w(
        'Attachment of event ${event.eventId} is not displayable as image: '
        'type=${data.detectFileType.runtimeType}, '
        'mimeType=${data.mimeType}, useThumbnail=$useThumbnail',
      );
    }
  }

  /// 将明文图片字节写入磁盘缓存，供下次应用重启秒开
  Future<void> _persistDiskCache(Uint8List bytes) async {
    await MxcImageDiskCache.write(
      rawKey: _cacheRawKey,
      bytes: bytes,
      isThumbnail: widget.isThumbnail,
      includeSize: _includeSizeInCache,
      width: widget.width,
      height: widget.height,
    );
  }

  Future<void> _tryLoad() async {
    if (_imageData != null) {
      return;
    }
    try {
      await _load();
    } on IOException catch (_) {
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      _tryLoad();
    } on MatrixException catch (e) {
      Logs().d('Unable to load image', e);
    } catch (e, s) {
      // 其它异常默认不会被任何分支捕获，气泡会一直停在转圈状态；
      // 记录完整堆栈，方便定位缩略图加载失败的真实原因。
      Logs().w('Unexpected error while loading mxc image', e, s);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;
    final ungzippedLottieData = data == null ? null : _ungzipLottie(data);

    Widget errorFallback(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      Logs().d('Unable to render mxc image', error, stackTrace);
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Icon(
            Icons.broken_image_outlined,
            size: min(widget.height ?? 64, 64),
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    final imageChild = data == null
        ? _MxcImagePlaceholder(
            width: widget.width,
            height: widget.height,
            placeholder: widget.placeholder,
          )
        : (ungzippedLottieData != null
              ? Lottie.memory(
                  ungzippedLottieData,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  errorBuilder: errorFallback,
                )
              : Image.memory(
                  data,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  filterQuality: widget.isThumbnail
                      ? FilterQuality.low
                      : FilterQuality.medium,
                  errorBuilder: errorFallback,
                ));

    return AnimatedCrossFade(
      duration: FluffyThemes.animationDuration,
      firstChild: ClipRRect(
        borderRadius: widget.borderRadius,
        child: imageChild,
      ),
      secondChild: _MxcImagePlaceholder(
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
      ),
      crossFadeState: hasData
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }
}

class _MxcImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? placeholder;

  const _MxcImagePlaceholder({
    required this.width,
    required this.height,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
  }
}

Uint8List? _ungzipLottie(Uint8List data) {
  // early return if the data is not gzipped
  if (data.length < 2 || data.first != 0x1f || data[1] != 0x8b) {
    return null;
  }

  // try decoding json
  try {
    final decompressed = GZipDecoder().decodeBytes(data);
    final jsonStr = utf8.decode(decompressed);
    final json = jsonDecode(jsonStr);
    if (json is Map && json.containsKey('v')) {
      return Uint8List.fromList(utf8.encode(jsonStr));
    }
  } catch (_) {
    return null;
  }

  return null;
}
