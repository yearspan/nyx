import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// 用于把当前发送流程绑定的 [UploadProgressSession] 传递给 SDK 内部
/// 发起的 HTTP 上传请求（Room.sendFileEvent 内部才会真正调用
/// Client.uploadContent，无法通过参数透传回调，只能借助 Zone 传递）。
const Object uploadProgressZoneKey = #fluffyUploadProgressSession;

/// 单条消息的上传进度。
///
/// 一次 [Room.sendFileEvent] 可能产生多个顺序执行的 HTTP 上传请求
/// （主文件 + 缩略图），本类负责把它们聚合成一个整体进度；
/// 失败重试时由上传层通过 [onRequestError] 丢弃未完成请求的计数，
/// 下一次 [onRequestStart] 重新统计，避免进度回跳后超过 100%。
class UploadProgressSession extends ChangeNotifier {
  UploadProgressSession(this.txid);

  /// 对应待发送事件的 transaction id，同时也是占位事件的 eventId。
  final String txid;

  /// 已成功完成的请求字节数。
  int _completedBytes = 0;

  /// 当前进行中请求的总字节数 / 已发送字节数。
  int _requestTotal = 0;
  int _requestSent = 0;

  /// 所有已开始请求的总字节数。
  int _totalBytes = 0;

  /// 用户取消信号：完成后，进行中的请求会被中断，之后该会话链路里的
  /// 所有请求一律快速失败，保证文件和消息都不会再发出去。
  final Completer<void> _cancelCompleter = Completer<void>();

  /// 供 http 层（Abortable.abortTrigger）监听的取消 Future。
  Future<void> get cancelTrigger => _cancelCompleter.future;

  /// 用户是否已取消本次发送。
  bool get isCancelled => _cancelCompleter.isCompleted;

  /// 取消本次发送，幂等，重复调用不会有副作用。
  ///
  /// 同时把 txid 记入 [UploadProgressManager] 的取消集合，供消息气泡
  /// 构建时判断：SDK 在 uploadContent 抛 MatrixException 后会立刻把
  /// 占位事件以 error 状态写回本地数据库（一次 fake sync），若不拦截，
  /// 在 removeCancelledSendPlaceholder 清理前的那一帧会闪现一个错误
  /// 气泡。取消集合让气泡直接不渲染，从视觉上彻底消除闪现。
  void cancel() {
    if (_cancelCompleter.isCompleted) return;
    _cancelCompleter.complete();
    UploadProgressManager.instance._cancelledTxids.add(txid);
    _notify(force: true);
  }

  DateTime? _lastNotify;

  /// 整体进度，区间 [0, 1]；总大小未知时返回 null（UI 回退为不确定转圈）。
  ///
  /// 注意：字节全部被 socket 接收后仍有内核缓冲排空、服务器处理与事件
  /// 发送的尾部耗时，因此会话活跃期间封顶在 99%，避免出现"显示 100%
  /// 但消息还要几秒才发送完成"的观感；会话结束后气泡直接退出发送态。
  double? get progress {
    if (_totalBytes <= 0) return null;
    final value = ((_completedBytes + _requestSent) / _totalBytes).clamp(
      0.0,
      1.0,
    );
    return value >= 1.0 ? 0.99 : value;
  }

  /// 一个新的 HTTP 上传请求开始（含重试）。
  void onRequestStart(int totalBytes) {
    _requestTotal = totalBytes;
    _requestSent = 0;
    if (totalBytes > 0) _totalBytes += totalBytes;
    _notify(force: true);
  }

  /// 当前请求上传进度更新。
  void onRequestProgress(int sentBytes) {
    if (sentBytes < _requestSent) return;
    _requestSent = sentBytes;
    _notify();
  }

  /// 当前请求成功完成（已收到服务器响应），锁定其字节数。
  void onRequestDone() {
    if (_requestTotal > 0) {
      _completedBytes += _requestTotal;
      _requestSent = _requestTotal;
    }
    _requestTotal = 0;
    _notify(force: true);
  }

  /// 当前请求失败（网络异常或错误状态码）。
  ///
  /// 丢弃该请求的计数；若外层重试，会重新走 [onRequestStart]。
  void onRequestError() {
    if (_requestTotal > 0) {
      _totalBytes -= _requestTotal;
      if (_totalBytes < 0) _totalBytes = 0;
    }
    _requestTotal = 0;
    _requestSent = 0;
    _notify(force: true);
  }

  /// 限制通知频率，避免大文件快速上传时每收到一个数据块都触发重建。
  void _notify({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastNotify != null &&
        now.difference(_lastNotify!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }
}

/// 活跃上传会话注册表，key 为占位事件的 eventId（即 txid）。
///
/// 消息气泡通过事件的 eventId 查询会话并监听进度；
/// 发送流程结束（成功或失败）后必须调用 [end] 释放。
class UploadProgressManager {
  UploadProgressManager._();

  static final UploadProgressManager instance = UploadProgressManager._();

  final Map<String, UploadProgressSession> _sessions = {};

  /// 已被用户取消发送的 txid 集合。
  ///
  /// SDK 在取消后的 uploadContent 异常里会通过 fake sync 把占位事件
  /// 以 error 状态写回本地数据库，导致一帧错误气泡闪现。本集合供
  /// [isCancelledTxid] 判断，消息气泡构建时直接跳过这些 txid，
  /// 从视觉上消除闪现。发送流程结束（[end]）时移除。
  final Set<String> _cancelledTxids = {};

  UploadProgressSession start(String txid) {
    final session = UploadProgressSession(txid);
    _sessions[txid] = session;
    return session;
  }

  UploadProgressSession? sessionFor(String txid) => _sessions[txid];

  /// 该 txid 对应的发送是否已被用户取消。
  bool isCancelledTxid(String txid) => _cancelledTxids.contains(txid);

  void end(String txid) {
    _sessions.remove(txid)?.dispose();
    _cancelledTxids.remove(txid);
  }
}

/// 清理取消发送后可能被 SDK "复活"的占位事件。
///
/// SDK 的上传/发送重试循环在超时（sendTimelineEventTimeout）后，会把
/// 占位事件以 error 状态通过 fake sync 重新写回数据库和时间线；而用户
/// 点取消时 [Event.cancelSend] 已经删掉了它，于是取消十几秒后又会冒出
/// 一个错误气泡。本函数只查本地数据库（不发网络请求），若发现该 txid
/// 的事件被写回则再次移除。
Future<void> removeCancelledSendPlaceholder(Room room, String txid) async {
  final event = await room.client.database.getEventById(txid, room);
  if (event != null && !event.status.isSent) {
    await event.cancelSend();
  }
}
