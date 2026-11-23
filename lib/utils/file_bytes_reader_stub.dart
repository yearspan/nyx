import 'dart:typed_data';

/// 占位实现（测试环境等无 dart:io / dart:html 时使用）。
Future<Uint8List> readFileBytes(String path) async =>
    throw UnsupportedError('readFileBytes is not supported on this platform');
