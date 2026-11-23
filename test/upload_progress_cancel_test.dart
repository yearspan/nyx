// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fluffychat/utils/upload_progress_http_client.dart';
import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/retry.dart';
import 'package:matrix/matrix.dart';

void main() {
  group('UploadProgressClient cancellation', () {
    late HttpServer server;
    late http.Client client;
    late Uri uploadUri;

    setUp(() async {
      server = await HttpServer.bind('localhost', 0);
      uploadUri = Uri.parse(
        'http://localhost:${server.port}/_matrix/media/v3/upload',
      );
      // 与生产链路保持一致：RetryClient(UploadProgressClient(IOClient))
      client = RetryClient(
        UploadProgressClient(IOClient()),
        retries: 4,
        when: (response) =>
            response.statusCode >= 500 || response.statusCode == 408,
      );
    });

    tearDown(() async {
      client.close();
      await server.close(force: true);
    });

    test('mid-upload abort interrupts the transfer', () async {
      var receivedBytes = 0;
      late StreamSubscription<List<int>> serverSub;
      server.listen((request) {
        serverSub = request.listen(
          (chunk) => receivedBytes += chunk.length,
          onDone: () => request.response.close(),
          cancelOnError: true,
        );
        // 暂停读取制造背压，保证取消发生时上传仍在进行中，
        // 而不是整块数据已经进入服务端缓冲区。
        serverSub.pause();
      });

      final session = UploadProgressManager.instance.start('cancel-mid');
      // 4MB 远超 loopback 的 socket 缓冲区，背压下必然传不完。
      final payload = Uint8List(4 * 1024 * 1024);
      final future = runZoned(
        () => client.send(http.Request('POST', uploadUri)..bodyBytes = payload),
        zoneValues: {uploadProgressZoneKey: session},
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(session.isCancelled, isFalse);
      session.cancel();

      // 中止后抛出 MatrixException：让 SDK 的 sendFileEvent 重试循环
      // 把它当作终态错误立即重抛，而不是每秒重试直到超时。
      await expectLater(future, throwsA(isA<MatrixException>()));
      expect(receivedBytes, lessThan(payload.length));
      UploadProgressManager.instance.end('cancel-mid');
      await serverSub.cancel();
    });

    test('requests fail fast without network after cancellation', () async {
      final session = UploadProgressManager.instance.start('cancel-fast');
      session.cancel();

      // 取消后链路内任意请求（含非上传请求）都应在客户端本地立即失败，
      // 不会真正发出网络请求。抛 MatrixException 是为了让 SDK 的
      // sendFileEvent 重试循环把它当作终态错误立即重抛，而不是每秒
      // 重试直到 sendTimelineEventTimeout（约8秒）。
      await expectLater(
        runZoned(
          () => client.send(http.Request('GET', uploadUri)),
          zoneValues: {uploadProgressZoneKey: session},
        ),
        throwsA(isA<MatrixException>()),
      );
      UploadProgressManager.instance.end('cancel-fast');
    });

    test('non-cancelled upload still delivers the full body', () async {
      final payload = Uint8List.fromList(
        List<int>.generate(500 * 1024, (i) => i % 256),
      );
      var receivedBytes = 0;
      server.listen((request) async {
        await for (final chunk in request) {
          receivedBytes += chunk.length;
        }
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'content_uri': 'mxc://x/y'}));
        await request.response.close();
      });

      final session = UploadProgressManager.instance.start('happy-path');
      final response = await runZoned(
        () => client.send(http.Request('POST', uploadUri)..bodyBytes = payload),
        zoneValues: {uploadProgressZoneKey: session},
      );

      expect(response.statusCode, 200);
      final body = await response.stream.toBytes();
      expect(utf8.decode(body), contains('content_uri'));
      expect(receivedBytes, payload.length);
      UploadProgressManager.instance.end('happy-path');
    });
  });
}
