import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/utils/file_bytes_reader_stub.dart'
    if (dart.library.html) 'package:fluffychat/utils/file_bytes_reader_web.dart'
    if (dart.library.io) 'package:fluffychat/utils/file_bytes_reader_native.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/video_thumbnail_stub.dart'
    if (dart.library.html) 'package:fluffychat/utils/video_thumbnail_web.dart'
    if (dart.library.io) 'package:fluffychat/utils/video_thumbnail_native.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

extension ResizeImage on XFile {
  Future<MatrixVideoFile> getVideoInfo({bool compress = true}) async {
    MediaInfo? mediaInfo;
    String? destinationPath;
    try {
      if (PlatformInfos.isMobile || PlatformInfos.isMacOS) {
        final result = await LightCompressor().compressVideo(
          path: path,
          videoQuality: VideoQuality.medium,
          android: AndroidConfig(isSharedStorage: false),
          ios: IOSConfig(saveInGallery: false),
          video: Video(videoName: name, targetSizeMb: 5),
        );
        if (result is OnFailure) {
          throw result.message;
        }
        if (result is OnSuccess) {
          destinationPath = result.destinationPath;
        }
        if (destinationPath != null) {
          mediaInfo = await LightCompressor().getMediaInfo(destinationPath);
        }
      }
    } catch (e, s) {
      Logs().w('Error while fetching video media info', e, s);
    }

    return MatrixVideoFile(
      bytes: destinationPath != null
          ? await readFileBytes(destinationPath)
          : await readFileBytes(path),
      name: name,
      mimeType: destinationPath != null
          ? lookupMimeType(destinationPath)
          : mimeType,
      width: mediaInfo?.width,
      height: mediaInfo?.height,
      duration: mediaInfo?.duration?.inMilliseconds,
    );
  }

  Future<MatrixImageFile?> getVideoThumbnail() async {
    // Mobile (Android/iOS) keeps using LightCompressor which gives
    // hardware-accelerated thumbnails.
    if (PlatformInfos.isMobile) {
      try {
        final thumbnailPath = await LightCompressor().getVideoThumbnail(path);
        final bytes = await readFileBytes(thumbnailPath);
        if (bytes.isEmpty) {
          Logs().w(
            'Video thumbnail extraction returned empty bytes: '
            'path=$path, thumbnail=$thumbnailPath',
          );
          return null;
        }
        final thumbnail = MatrixImageFile(bytes: bytes, name: name);
        Logs().d(
          'Video thumbnail generated: ${bytes.length} bytes, '
          'mimeType=${thumbnail.mimeType}, path=$path',
        );
        return thumbnail;
      } catch (e, s) {
        // 取帧失败（插件抛 ThumbnailException / 平台异常）时返回 null，
        // 事件将不带 thumbnail_url，聊天气泡因此没有视频封面。
        Logs().w('Failed to extract video thumbnail: path=$path', e, s);
      }
      return null;
    }

    // Desktop (macOS/Linux/Windows) & Web: delegate to a platform-specific
    // implementation (native: media_kit/mpv; web: HTMLVideoElement + canvas).
    // Mobile (Android/iOS) is handled above via LightCompressor.
    try {
      final bytes = await extractVideoThumbnail(
        path,
        await readFileBytes(path),
        mimeType ?? 'video/mp4',
      );
      if (bytes == null || bytes.isEmpty) {
        Logs().w('Video thumbnail extraction returned empty bytes: path=$path');
        return null;
      }
      final thumbnail = MatrixImageFile(bytes: bytes, name: name);
      Logs().d(
        'Video thumbnail generated: ${bytes.length} bytes, '
        'mimeType=${thumbnail.mimeType}, path=$path',
      );
      return thumbnail;
    } catch (e, s) {
      Logs().w('Failed to extract video thumbnail: path=$path', e, s);
      return null;
    }
  }
}
