import 'dart:async';

import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'upload_progress_http_client_stub.dart'
    if (dart.library.js_interop) 'upload_progress_http_client_web.dart'
    as platform;

/// 包装 Matrix SDK 使用的 [http.Client]，把媒体上传请求转换为真实的
/// 上传进度，上报给当前 Zone 中绑定的 [UploadProgressSession]。
///
/// Matrix 协议本身没有上传进度字段，SDK 的 uploadContent 也不暴露回调，
/// 但上传本质是一个带 body 的 HTTP 请求：native 端通过把请求体改造成
/// 带计数的数据流、web 端通过 XMLHttpRequest 的 upload.onprogress
/// 即可获得字节级进度。非上传请求、以及未绑定会话的上传（表情、资料
/// 头像等）直接透传，行为与原客户端完全一致。
class UploadProgressClient extends http.BaseClient {
  UploadProgressClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final session = Zone.current[uploadProgressZoneKey];
    if (session is! UploadProgressSession) {
      return _inner.send(request);
    }
    // 取消后该发送链路内的所有请求都快速失败——不仅是进行中的媒体
    // 上传，还包括上传完成后提交消息的 /send 请求，避免出现"文件
    // 传完了才点取消，消息照样发出去"的竞态。
    //
    // 必须抛 [MatrixException]：SDK 的 sendFileEvent 上传重试循环只把
    // MatrixException 当作终态错误立即设置 error 状态并重抛；其他异常
    // 会被当作网络抖动每秒重试一次，直到 sendTimelineEventTimeout（约8秒）
    // 才超时——这正是取消后延迟闪现错误气泡的根因。
    if (session.isCancelled) {
      throw MatrixException.fromJson(const {
        'errcode': 'M_UNKNOWN',
        'error': 'Cancelled by user',
      });
    }
    if (!_isMediaUpload(request)) {
      return _inner.send(request);
    }
    return platform.sendUploadWithProgress(_inner, request, session);
  }

  @override
  void close() => _inner.close();

  /// 匹配 `_matrix/media/v1|v3/upload[/...]` 媒体上传请求。
  static bool _isMediaUpload(http.BaseRequest request) {
    if (request.method != 'POST' && request.method != 'PUT') return false;
    final segments = request.url.pathSegments;
    return segments.contains('media') && segments.contains('upload');
  }
}
