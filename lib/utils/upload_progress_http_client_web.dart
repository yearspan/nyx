import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

/// web 端上传实现。
///
/// package:http 的 BrowserClient 基于 fetch，请求体会整体缓冲且
/// fetch 不提供上传进度事件，因此媒体上传改用 XMLHttpRequest：
/// `xhr.upload.onprogress` 会按已发送字节持续回调，从而拿到真实进度。
/// 返回值仍封装成标准 [http.StreamedResponse]，对上层 SDK 透明。
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
  final bytes = await request.finalize().toBytes();
  final total = request.contentLength ?? bytes.length;
  session.onRequestStart(total);

  final xhr = web.XMLHttpRequest();
  // MDN 建议在 open() 之前挂载 upload 监听器，规避部分浏览器的兼容问题。
  xhr.upload.onprogress = ((web.Event event) {
    final progressEvent = event as web.ProgressEvent;
    // 即便 lengthComputable 为 false，loaded 仍然有意义，总量取请求体大小。
    session.onRequestProgress(progressEvent.loaded);
  }).toJS;
  // 用户取消：中断进行中的 XHR，触发 onabort 走统一的中止异常分支。
  // 请求完成后 abort 是无副作用的空操作，无需额外判断 readyState。
  // 同样不能 tear-off xhr.abort（interop external 成员的 tear-off 会
  // 导致 dart2js 编译报错），必须保留闭包。
  unawaited(
    session.cancelTrigger.whenComplete(
      // ignore: unnecessary_lambdas
      () {
        xhr.abort();
      },
    ),
  );

  final completer = Completer<void>();
  xhr.onload = (() {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  xhr.onerror = (() {
    if (!completer.isCompleted) {
      completer.completeError(
        http.ClientException('XMLHttpRequest upload failed', request.url),
      );
    }
  }).toJS;
  xhr.onabort = (() {
    if (!completer.isCompleted) {
      completer.completeError(http.RequestAbortedException(request.url));
    }
  }).toJS;
  xhr.ontimeout = (() {
    if (!completer.isCompleted) {
      completer.completeError(
        http.ClientException('XMLHttpRequest upload timed out', request.url),
      );
    }
  }).toJS;

  xhr.open(request.method, request.url.toString());
  xhr.responseType = 'arraybuffer';
  // 不能直接 tear-off xhr.setRequestHeader：extension type 的 external
  // interop 成员禁止 tear-off（dart2js 编译报错），必须用闭包显式调用。
  // ignore: unnecessary_lambdas
  request.headers.forEach((name, value) {
    xhr.setRequestHeader(name, value);
  });
  xhr.send(bytes.toJS);

  try {
    await completer.future;
  } catch (_) {
    session.onRequestError();
    // 用户取消导致的 XHR 中止：必须转成 MatrixException，否则 SDK 的
    // sendFileEvent 重试循环会把它当网络抖动每秒重试直到超时。
    if (session.isCancelled) {
      throw MatrixException.fromJson(const {
        'errcode': 'M_UNKNOWN',
        'error': 'Cancelled by user',
      });
    }
    rethrow;
  }

  if (xhr.status == 0) {
    session.onRequestError();
    throw http.ClientException('XMLHttpRequest upload failed', request.url);
  }

  if (xhr.status >= 400) {
    session.onRequestError();
  } else {
    session.onRequestDone();
  }

  final responseBuffer = (xhr.response as JSArrayBuffer).toDart;
  final responseBytes = Uint8List.view(responseBuffer);
  return http.StreamedResponse(
    http.ByteStream(Stream.value(responseBytes)),
    xhr.status,
    headers: _parseResponseHeaders(xhr.getAllResponseHeaders()),
    reasonPhrase: xhr.statusText,
    request: request,
  );
}

/// 解析 XHR 的原始响应头（CRLF 分隔的 `name: value` 文本）。
Map<String, String> _parseResponseHeaders(String raw) {
  final headers = <String, String>{};
  for (final line in raw.split('\r\n')) {
    if (line.isEmpty) continue;
    final index = line.indexOf(':');
    if (index <= 0) continue;
    headers[line.substring(0, index).trim().toLowerCase()] = line
        .substring(index + 1)
        .trim();
  }
  return headers;
}
