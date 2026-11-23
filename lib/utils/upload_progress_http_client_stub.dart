import 'dart:typed_data';

import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// 单次交给 socket 写入的数据块大小。
///
/// SDK 的上传请求体是整块内存字节（Request.finalize 只产生一个 stream
/// 事件），若直接对整块计数，会在数据刚进入 socket 缓冲区时就跳到
/// 100%，而网络发送其实才刚开始。切成固定小块后，dart:io 的 socket
/// 背压（内核/TLS 缓冲区满时暂停 stream 订阅）会按真实网络发送速度
/// 逐块拉取，计数因此与实际发出的字节保持一致。
const int _uploadChunkSize = 32 * 1024;

/// native 端上传实现：把请求体重切成小块，借助 IOClient → HttpClient
/// → socket 的 addStream 背压链，上报接近真实网络发送速度的字节进度。
Future<http.StreamedResponse> sendUploadWithProgress(
  http.Client inner,
  http.BaseRequest request,
  UploadProgressSession session,
) async {
  if (session.isCancelled) {
    throw MatrixException.fromJson(const {
      'errcode': 'M_UNKNOWN',
      'error': 'Cancelled by user',
    });
  }
  // SDK 上传的本来就是内存字节（MatrixFile.bytes），toBytes 不会带来
  // 额外的内存压力，同时可兼容任意形态的请求体流。
  final bytes = await request.finalize().toBytes();
  final total = request.contentLength ?? bytes.length;
  session.onRequestStart(total);

  var sent = 0;
  // async* 在订阅被 pause 时会挂起在 yield 处，socket 缓冲区排空后才
  // 继续生产下一块，这是进度能反映真实发送速度的关键。
  Stream<List<int>> buildChunkedStream() async* {
    for (var offset = 0; offset < bytes.length; offset += _uploadChunkSize) {
      final end = offset + _uploadChunkSize > bytes.length
          ? bytes.length
          : offset + _uploadChunkSize;
      final chunk = Uint8List.sublistView(bytes, offset, end);
      yield chunk;
      sent += chunk.length;
      session.onRequestProgress(sent);
    }
  }

  final progressRequest =
      _ProgressRequest(
          request.method,
          request.url,
          http.ByteStream(buildChunkedStream()),
          session.cancelTrigger,
        )
        ..headers.addAll(request.headers)
        ..contentLength = request.contentLength
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;

  try {
    final response = await inner.send(progressRequest);
    if (response.statusCode >= 400) {
      session.onRequestError();
    } else {
      session.onRequestDone();
    }
    return response;
  } catch (_) {
    session.onRequestError();
    // 用户取消导致的 socket 中断：必须转成 MatrixException，否则 SDK
    // 的 sendFileEvent 重试循环会把它当网络抖动每秒重试直到超时。
    if (session.isCancelled) {
      throw MatrixException.fromJson(const {
        'errcode': 'M_UNKNOWN',
        'error': 'Cancelled by user',
      });
    }
    rethrow;
  }
}

/// 携带自定义（分块 + 进度计数）body 流的请求，除 body 外完整复制原请求的
/// method、url、headers 与连接属性，保证 IOClient 行为与普通 Request 一致。
///
/// 混入 [http.Abortable]：用户取消时 IOClient 会调用底层
/// HttpClientRequest.abort 中断 socket 写入，正在进行的上传立即失败，
/// 而不是等整个文件传完。
class _ProgressRequest extends http.BaseRequest with http.Abortable {
  final http.ByteStream _body;

  @override
  final Future<void>? abortTrigger;

  _ProgressRequest(super.method, super.url, this._body, this.abortTrigger);

  @override
  http.ByteStream finalize() {
    super.finalize();
    return _body;
  }
}
