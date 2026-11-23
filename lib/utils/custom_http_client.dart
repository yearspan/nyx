import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/config/isrg_x1.dart';
import 'package:fluffychat/config/isrg_x2.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/upload_progress_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/retry.dart' as retry;

/// Custom HTTP client that adds the ISRG Root certificates used by Let's
/// Encrypt. Older Android versions may not include these roots in their
/// trust store, so we ship them ourselves to ensure TLS connections to
/// Let's Encrypt–signed servers continue to work.
class CustomHttpClient {
  static HttpClient customHttpClient() {
    final context = SecurityContext.defaultContext;

    try {
      context.setTrustedCertificatesBytes(utf8.encode(ISRG_X1));
      context.setTrustedCertificatesBytes(utf8.encode(ISRG_X2));
    } on TlsException catch (e) {
      if (e.osError != null &&
          e.osError!.message.contains('CERT_ALREADY_IN_HASH_TABLE')) {
      } else {
        rethrow;
      }
    }

    return HttpClient(context: context);
  }

  /// 创建带重试的 HTTP 客户端。
  ///
  /// 默认 [retry.RetryClient] 只重试 GET/HEAD 等安全方法，且只重试
  /// [http.ClientException]。但 MatrixRTC 入会时向 SFU 发起的是 POST
  /// 请求，且安卓弱网下偶发 [HandshakeException]（TLS 握手被中断）、
  /// [SocketException] 等 [IOException]，这些都不在默认重试范围内，
  /// 一次失败就会导致通话无法建立。这里放宽策略：对所有方法的网络层
  /// 错误（IOException）和 5xx 响应都重试。
  ///
  /// [UploadProgressClient] 放在 RetryClient 内层：重试时 RetryClient
  /// 会为每次尝试复制一份新请求，进度客户端因此能在每次尝试时重新
  /// 统计上传进度。
  static http.Client createHTTPClient() => retry.RetryClient(
    UploadProgressClient(
      PlatformInfos.isAndroid ? IOClient(customHttpClient()) : http.Client(),
    ),
    retries: 4,
    when: (response) =>
        response.statusCode >= 500 || response.statusCode == 408,
    whenError: (error, stackTrace) => error is IOException,
    delay: (attemptCount) => Duration(milliseconds: 200 * (attemptCount + 1)),
  );
}
