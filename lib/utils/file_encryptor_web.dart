import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

/// Web 端使用浏览器原生 Web Crypto API（SubtleCrypto）加密文件。
///
/// 原因：matrix SDK 的 `encryptFile` 直接同步调用 vodozemac wasm FFI
/// （CryptoUtils.aesCtr/sha256），大文件在 wasm 中会触发 `unreachable`
/// （内存不足/Rust panic）。SubtleCrypto 是浏览器原生异步实现，既
/// 绕开 wasm 限制，又不阻塞主线程。
///
/// 算法与 Matrix 规范一致：AES-256-CTR（IV 高 64 位随机、低 64 位为
/// 计数器初值 0）+ SHA-256 密文哈希，base64 无填充编码。
Future<EncryptedFile?> encryptFileInBackground(Uint8List bytes) async {
  final crypto = web.window.crypto;
  final subtle = crypto.subtle;

  // 256 位随机密钥
  final keyJS = Uint8List(32).toJS;
  crypto.getRandomValues(keyJS);
  final keyBytes = keyJS.toDart;

  // IV 共 128 位：高 64 位随机，低 64 位为计数器（初值 0）
  final iv = Uint8List(16);
  final randomPrefixJS = Uint8List(8).toJS;
  crypto.getRandomValues(randomPrefixJS);
  iv.setRange(0, 8, randomPrefixJS.toDart);
  // iv[8..16] 保持 0，即计数器初值

  // 导入 AES-CTR 密钥
  final cryptoKey = await subtle
      .importKey(
        'raw',
        keyJS as JSObject,
        'AES-CTR'.toJS,
        false,
        ['encrypt'].map((e) => e.toJS).toList().toJS,
      )
      .toDart;

  // AES-CTR 加密，counter 长度 64 位
  final algorithm = {
    'name': 'AES-CTR',
    'counter': iv.toJS,
    'length': 64,
  }.jsify();
  final encryptedJS = await subtle
      .encrypt(
        algorithm as web.AlgorithmIdentifier,
        cryptoKey,
        bytes.toJS,
      )
      .toDart;
  final ciphertext = (encryptedJS as JSArrayBuffer).toDart.asUint8List();

  // SHA-256 密文哈希
  final hashJS =
      await subtle.digest('SHA-256'.toJS, ciphertext.toJS).toDart;
  final hash = (hashJS as JSArrayBuffer).toDart.asUint8List();

  return EncryptedFile(
    data: ciphertext,
    k: base64Url.encode(keyBytes).replaceAll('=', ''),
    iv: base64.encode(iv).replaceAll('=', ''),
    sha256: base64.encode(hash).replaceAll('=', ''),
  );
}
