import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: 使用浏览器原生 HTMLVideoElement + Canvas 提取视频首帧作为缩略图。
///
/// 本地选择的视频文件通过 `URL.createObjectURL` 转为 blob URL（同源），
/// 不存在 CORS 污染 canvas 的问题；绝大多数浏览器可解码 H.264/MP4，
/// 因此该方案在"发送本地视频"场景下是稳定可用的。
Future<Uint8List?> extractVideoThumbnail(
  String path,
  Uint8List bytes,
  String mimeType,
) async {
  final tag = '[VideoThumb]';
  print('$tag start: path=$path, bytes=${bytes.length}, mime=$mimeType');

  final completer = Completer<Uint8List?>();
  var captured = false;
  var seeked = false;

  // 1) 从字节创建 Blob URL（同源，canvas 不会被污染）
  final blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  print('$tag blob url created: $url');

  // 2) 创建隐藏的 video 元素用于解码
  // 注意：不能设置 crossOrigin='anonymous'，blob URL 是同源的，
  // 设置 crossOrigin 反而会让浏览器用 CORS 模式加载而失败。
  final video = web.document.createElement('video') as web.HTMLVideoElement
    ..muted = true
    ..setAttribute('playsinline', '')
    ..preload = 'auto';
  // 移出可视区域，避免影响布局
  video.style
    ..position = 'fixed'
    ..top = '-9999px'
    ..left = '-9999px'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0'
    ..pointerEvents = 'none';

  void cleanup() {
    web.URL.revokeObjectURL(url);
    video.remove();
  }

  /// 把当前视频帧绘制到 canvas 并导出为 JPEG 字节
  Future<void> captureFrame() async {
    if (captured) return;
    captured = true;
    try {
      final vw = video.videoWidth;
      final vh = video.videoHeight;
      print('$tag captureFrame: videoSize=${vw}x$vh, readyState=${video.readyState}');
      if (vw <= 0 || vh <= 0) {
        print('$tag captureFrame: invalid video size, abort');
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = vw
            ..height = vh;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.drawImage(video, 0, 0, vw, vh);

      final blobCompleter = Completer<web.Blob?>();
      canvas.toBlob(
        ((web.Blob? b) {
          blobCompleter.complete(b);
        }).toJS,
        'image/jpeg',
        0.8.jsify(),
      );
      final outBlob = await blobCompleter.future;
      if (outBlob == null) {
        print('$tag captureFrame: toBlob returned null');
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final reader = web.FileReader();
      reader.onloadend = ((web.Event _) {
        final result = reader.result;
        cleanup();
        if (!completer.isCompleted) {
          final thumb = result.isA<JSArrayBuffer>()
              ? (result as JSArrayBuffer).toDart.asUint8List()
              : null;
          print('$tag captureFrame: thumb=${thumb?.length} bytes');
          completer.complete(thumb);
        }
      }).toJS;
      reader.onerror = ((web.Event _) {
        print('$tag captureFrame: FileReader error');
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
      }).toJS;
      reader.readAsArrayBuffer(outBlob);
    } catch (e) {
      print('$tag captureFrame: exception=$e');
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
    }
  }

  /// seek 到 0.1s（避开部分视频第 0 帧黑屏），失败则直接抓当前帧
  void seekAndCapture() {
    try {
      print('$tag seeking to 0.1s');
      video.currentTime = 0.1;
    } catch (e) {
      print('$tag seek failed: $e, capture current frame');
      captureFrame();
    }
  }

  // 3) 先挂事件监听，再设置 src（避免错过初始事件）
  video.oncanplay = ((web.Event _) {
    print('$tag oncanplay, readyState=${video.readyState}');
    if (!seeked) {
      seeked = true;
      seekAndCapture();
    }
  }).toJS;

  video.onloadeddata = ((web.Event _) {
    print('$tag onloadeddata, readyState=${video.readyState}');
    if (!seeked) {
      seeked = true;
      seekAndCapture();
    }
  }).toJS;

  video.onseeked = ((web.Event _) {
    print('$tag onseeked, currentTime=${video.currentTime}');
    captureFrame();
  }).toJS;

  video.onerror = ((web.Event _) {
    print('$tag onerror: video failed to load');
    cleanup();
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;

  // 4) 设置 src 并加入 DOM，触发加载
  video.src = url;
  web.document.body?.appendChild(video);
  video.load();
  print('$tag video.src set and load() called');

  // 5) 兜底：如果 seeked 迟迟不触发，500ms 后直接抓帧
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    if (!captured && video.readyState >= 2) {
      print('$tag fallback: readyState=${video.readyState}, capturing');
      captureFrame();
    }
  });

  // 6) 超时保护：10s 还没出结果就放弃
  Future.delayed(const Duration(seconds: 10), () {
    if (!completer.isCompleted) {
      print('$tag timeout, aborting');
      cleanup();
      completer.complete(null);
    }
  });

  return completer.future;
}
