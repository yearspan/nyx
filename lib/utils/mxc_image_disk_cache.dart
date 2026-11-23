import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 明文图片磁盘缓存（独立于 SDK 加密数据库，重启后仍可秒开）。
///
/// 由 [MxcImage] 与图片浏览页共享，避免缩略图/原图被重复下载。
class MxcImageDiskCache {
  static Directory? _dir;

  static Future<Directory> get _directory async {
    if (_dir != null) return _dir!;
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/mxc_images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// 基于 cacheKey/eventId/uri 生成稳定的磁盘缓存文件名。
  ///
  /// - [isThumbnail] 区分缩略图与原图，避免互相覆盖。
  /// - 仅当 [includeSize] 为 true（如按 uri 请求头像的场景）才拼接尺寸后缀，
  ///   避免不同尺寸的缩略图互相覆盖。
  static String buildFileName({
    required String rawKey,
    required bool isThumbnail,
    double? width,
    double? height,
    bool includeSize = false,
  }) {
    final safeKey = rawKey.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final suffix = isThumbnail ? '_thumb' : '_full';
    final sizeTag = includeSize
        ? '_${width?.toInt() ?? 0}x${height?.toInt() ?? 0}'
        : '';
    return '$safeKey$suffix$sizeTag';
  }

  /// 读取磁盘缓存，命中则返回字节，否则返回 null。
  static Future<Uint8List?> read({
    required String rawKey,
    required bool isThumbnail,
    double? width,
    double? height,
    bool includeSize = false,
  }) async {
    try {
      final dir = await _directory;
      final fileName = buildFileName(
        rawKey: rawKey,
        isThumbnail: isThumbnail,
        width: width,
        height: height,
        includeSize: includeSize,
      );
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {
      // 磁盘缓存读取失败不影响上层流程
    }
    return null;
  }

  /// 将明文图片字节写入磁盘缓存（已存在则跳过，避免重复写入）。
  static Future<void> write({
    required String rawKey,
    required Uint8List bytes,
    required bool isThumbnail,
    double? width,
    double? height,
    bool includeSize = false,
  }) async {
    try {
      final dir = await _directory;
      final fileName = buildFileName(
        rawKey: rawKey,
        isThumbnail: isThumbnail,
        width: width,
        height: height,
        includeSize: includeSize,
      );
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {
      // 磁盘缓存写入失败不影响显示
    }
  }

  /// 清除指定 key 的缓存（缩略图 + 原图）。
  static Future<void> clear(String rawKey) async {
    try {
      final dir = await _directory;
      final safeKey = rawKey.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      await for (final entity in dir.list()) {
        if (entity is File &&
            (entity.path.endsWith('${safeKey}_thumb') ||
                entity.path.endsWith('${safeKey}_full'))) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
}
