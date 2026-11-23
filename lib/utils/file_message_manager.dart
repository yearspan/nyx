import 'dart:async';
import 'dart:io';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
// 与 open_filex 存在同名的 OpenResult/ResultType，加前缀避免冲突
import 'package:ym_open_file_plus/ym_open_file_plus.dart' as ym;

/// 下载状态
enum DownloadStatus { checking, cached, notCached, downloading }

/// 单个文件的下载状态 + 进度
class DownloadState {
  final DownloadStatus status;
  final double progress;

  const DownloadState({
    this.status = DownloadStatus.checking,
    this.progress = 0,
  });

  DownloadState copyWith({DownloadStatus? status, double? progress}) {
    return DownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }
}

/// 文件消息的下载与打开工具（仿 Telegram 风格）：
/// - 本地已缓存：直接打开
/// - 未缓存：下载后打开
/// 下载的文件持久化到应用缓存目录，下次无需重新下载。
///
/// 下载状态通过 [ValueNotifier] 暴露，解决列表滚动时 widget 重建导致
/// 进度丢失的问题。
///
/// 进度更新使用定时器（10fps）而非逐数据块回调，避免频繁 UI 重建阻塞
/// 事件循环导致 TCP 接收缓冲区满、下载被流控拖慢。
class FileMessageManager {
  /// 按事件 ID 保存下载状态的 ValueNotifier，跨 widget 生命周期持久
  static final Map<String, ValueNotifier<DownloadState>> _states = {};

  /// 取消信号：取消时 complete 对应的 Completer
  static final Map<String, Completer<void>> _cancelSignals = {};

  /// 流式下载的 stream 订阅，用于取消时中断
  static final Map<String, StreamSubscription<List<int>>> _subscriptions = {};

  /// 进度定时器，按 eventId 索引
  static final Map<String, Timer> _progressTimers = {};

  /// 获取指定事件的下载状态 ValueNotifier（不存在则创建 checking 状态）
  static ValueNotifier<DownloadState> getState(String eventId) {
    return _states.putIfAbsent(
      eventId,
      () => ValueNotifier(const DownloadState()),
    );
  }

  /// 判断该事件的附件是否已在本地缓存中
  static Future<bool> isCached(Event event) async {
    final path = await _localPath(event);
    if (await File(path).exists()) return true;
    try {
      await event.downloadAndDecryptAttachment(fromLocalStoreOnly: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 下载附件并保存到本地缓存目录，返回本地文件路径。
  /// 同时更新 [getState] 暴露的下载状态。
  static Future<String> download(Event event) async {
    final state = getState(event.eventId);
    final eventId = event.eventId;

    // 已有活跃下载：直接等待其完成（用取消信号判断，比 status 更可靠）
    final existingCancel = _cancelSignals[eventId];
    if (existingCancel != null && !existingCancel.isCompleted) {
      final completer = Completer<String>();
      void listener() {
        if (state.value.status == DownloadStatus.cached) {
          state.removeListener(listener);
          completer.complete(_localPath(event));
        } else if (state.value.status == DownloadStatus.notCached) {
          state.removeListener(listener);
          completer.completeError('cancelled');
        }
      }

      state.addListener(listener);
      return completer.future;
    }

    // 同步标记开始下载（在第一个 await 之前，避免竞态）
    final cancelSignal = Completer<void>();
    _cancelSignals[eventId] = cancelSignal;
    state.value = state.value.copyWith(
      status: DownloadStatus.downloading,
      progress: 0,
    );

    // 本地已缓存：直接返回路径
    final localPath = await _localPath(event);
    if (await File(localPath).exists()) {
      _cancelSignals.remove(eventId);
      state.value = state.value.copyWith(
        status: DownloadStatus.cached,
        progress: 1,
      );
      return localPath;
    }

    final fileSize =
        event.infoMap.tryGet<int>('size') ??
        event.content
            .tryGetMap<String, Object?>('info')
            ?.tryGet<int>('size');

    try {
      final path = event.isAttachmentEncrypted
          ? await _downloadEncrypted(event, fileSize, state, cancelSignal)
          : await _streamDownloadToFile(
              event,
              fileSize,
              state,
              cancelSignal,
            );

      if (cancelSignal.isCompleted) {
        _cleanup(eventId);
        state.value = state.value.copyWith(status: DownloadStatus.notCached);
        throw Exception('cancelled');
      }

      state.value = state.value.copyWith(
        status: DownloadStatus.cached,
        progress: 1,
      );
      return path;
    } catch (_) {
      _cleanup(eventId);
      state.value = state.value.copyWith(status: DownloadStatus.notCached);
      rethrow;
    } finally {
      _cancelSignals.remove(eventId);
    }
  }

  /// 取消指定事件的下载
  static void cancelDownload(String eventId) {
    _cancelSignals[eventId]?.complete();
    // 中断流式下载的订阅
    _subscriptions[eventId]?.cancel();
    _subscriptions.remove(eventId);
  }

  /// 清理取消信号、订阅和进度定时器
  static void _cleanup(String eventId) {
    _subscriptions[eventId]?.cancel();
    _subscriptions.remove(eventId);
    _progressTimers.remove(eventId)?.cancel();
    _cancelSignals.remove(eventId);
  }

  /// 启动节流进度定时器（10fps），通过读取 [receivedHolder] 中的字节数更新 UI。
  /// 这样 stream listener 只需更新一个 int，不触发 widget 重建，
  /// 避免阻塞 socket 读取导致 TCP 流控拖慢下载。
  static void _startProgressTimer(
    String eventId,
    ValueNotifier<DownloadState> state,
    int? fileSize,
    _IntHolder receivedHolder,
  ) {
    _progressTimers[eventId]?.cancel();
    _progressTimers[eventId] = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (fileSize != null && fileSize > 0) {
          state.value = state.value.copyWith(
            progress: (receivedHolder.value / fileSize).clamp(0.0, 1.0),
          );
        }
      },
    );
  }

  /// 未加密文件的流式下载：HTTP 响应流直接写入磁盘文件。
  static Future<String> _streamDownloadToFile(
    Event event,
    int? fileSize,
    ValueNotifier<DownloadState> state,
    Completer<void> cancelSignal,
  ) async {
    final client = event.room.client;
    final mxcUrl = event.attachmentMxcUrl;
    if (mxcUrl == null) {
      throw Exception('No attachment URL');
    }

    final downloadUri = await mxcUrl.getDownloadUri(client);
    final request = http.Request('GET', downloadUri);
    if (client.accessToken != null) {
      request.headers['authorization'] = 'Bearer ${client.accessToken}';
    }

    final response = await client.httpClient.send(request);
    if (response.statusCode != 200) {
      throw Exception(
        'Download failed with status ${response.statusCode}',
      );
    }

    final localPath = await _localPath(event);
    final localFile = File(localPath);
    if (await localFile.exists()) {
      await localFile.delete();
    }

    // 已接收字节数：stream listener 只更新这个变量，不碰 UI
    final received = _IntHolder();
    _startProgressTimer(event.eventId, state, fileSize, received);

    final sink = localFile.openWrite();
    final completer = Completer<void>();

    final subscription = response.stream.listen(
      (chunk) {
        sink.add(chunk);
        received.value += chunk.length;
        // 不在这里更新 UI —— 定时器每 100ms 批量更新一次
      },
      onDone: completer.complete,
      onError: completer.completeError,
    );
    _subscriptions[event.eventId] = subscription;

    // 等待下载完成或被取消
    await Future.any([completer.future, cancelSignal.future]);

    await subscription.cancel();
    await sink.close();
    _subscriptions.remove(event.eventId);
    _progressTimers.remove(event.eventId)?.cancel();

    if (cancelSignal.isCompleted) {
      // 取消：删除已下载的部分文件
      if (await localFile.exists()) {
        await localFile.delete();
      }
      throw Exception('cancelled');
    }

    state.value = state.value.copyWith(progress: 1.0);
    return localPath;
  }

  /// 加密文件下载：走 SDK 的下载 + 解密流程。
  /// 注：SDK 的 downloadAndDecryptAttachment 不支持中途取消，
  /// 取消信号仅用于恢复 UI 状态，实际下载会跑完。
  static Future<String> _downloadEncrypted(
    Event event,
    int? fileSize,
    ValueNotifier<DownloadState> state,
    Completer<void> cancelSignal,
  ) async {
    // SDK 的 onDownloadProgress 每个数据块都会回调，
    // 这里只更新计数器，由定时器节流后刷新 UI
    final received = _IntHolder();
    _startProgressTimer(event.eventId, state, fileSize, received);

    final matrixFile = await event.downloadAndDecryptAttachment(
      onDownloadProgress: fileSize == null
          ? null
          : (bytes) => received.value = bytes,
    );

    _progressTimers.remove(event.eventId)?.cancel();

    if (cancelSignal.isCompleted) {
      throw Exception('cancelled');
    }
    state.value = state.value.copyWith(progress: 1.0);
    return saveToLocal(event, matrixFile);
  }

  /// 计算事件附件在本地缓存目录的路径
  static Future<String> _localPath(Event event) async {
    final dir = await getTemporaryDirectory();
    final fileName = event.content.tryGet<String>('filename') ?? event.body;
    final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
    return '${dir.path}/${event.eventId}$ext';
  }

  /// 把 MatrixFile 保存到本地缓存目录，返回路径
  static Future<String> saveToLocal(Event event, MatrixFile file) async {
    final localPath = await _localPath(event);
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      await localFile.writeAsBytes(file.bytes);
    }
    return localFile.path;
  }

  /// 用系统默认应用打开文件。
  /// - Android / iOS：使用 open_filex
  /// - 桌面 / Web：使用 ym_open_file_plus（支持 Linux / macOS / Windows / Web）
  ///
  /// 打开失败（如系统中没有可处理该文件类型的应用、权限被拒绝）时
  /// 抛出 [OpenFileException]，调用方需捕获并向用户展示提示，
  /// 避免静默失败表现为"点击没反应"。
  static Future<void> open(String path) async {
    if (PlatformInfos.isMobile) {
      final result = await OpenFilex.open(path);
      if (result.type == ResultType.done) return;

      // Android 上部分设备没有应用注册插件推断出的具体 MIME
      // （如 zip 被推断为非标准的 application/x-zip-compressed，
      // 而部分文件管理器只注册了 application/zip），
      // 用通配 MIME 兜底再试一次，让接收方按文件扩展名自行识别。
      if (PlatformInfos.isAndroid &&
          result.type == ResultType.noAppToOpen) {
        final fallback = await OpenFilex.open(path, type: '*/*');
        if (fallback.type == ResultType.done) return;
        Logs().w(
          'Open file with wildcard MIME failed: '
          '${fallback.type} ${fallback.message}',
        );
        throw OpenFileException(fallback.type.name, fallback.message);
      }

      Logs().w('Open file failed: ${result.type} ${result.message}');
      throw OpenFileException(result.type.name, result.message);
    } else {
      final result = await ym.OpenFile.open(path);
      if (result.type != ym.ResultType.done) {
        Logs().w('Open file failed: ${result.type} ${result.message}');
        throw OpenFileException(result.type.name, result.message);
      }
    }
  }
}

/// 打开文件失败异常：[failureType] 对应平台返回的 ResultType 名称，
/// [message] 为平台给出的原始错误信息
class OpenFileException implements Exception {
  final String failureType;
  final String? message;

  const OpenFileException(this.failureType, [this.message]);

  @override
  String toString() => 'OpenFileException($failureType: $message)';
}

/// 可变 int 持有器，用于在闭包中共享计数器
class _IntHolder {
  int value = 0;
}
