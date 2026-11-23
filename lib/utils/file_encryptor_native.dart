import 'dart:isolate';
import 'dart:typed_data';

import 'package:fluffychat/config/app_config.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart';

/// 大文件加密阈值：低于此值直接在主 isolate 加密（耗时可忽略），
/// 高于此值移到后台 isolate 避免主线程卡死（36MB 文件同步加密约 6s）。
const int preEncryptThresholdBytes = 5 * 1024 * 1024;

/// 后台 isolate 加密参数：仅传可转移的字节数据，避免大数组复制。
class _EncryptArgs {
  final TransferableTypedData input;
  const _EncryptArgs(this.input);
}

/// 后台 isolate 加密结果：密文用 [TransferableTypedData] 零拷贝回传，
/// k/iv/sha256 是短字符串，直接随消息传递。
class _EncryptResult {
  final TransferableTypedData data;
  final String k;
  final String iv;
  final String sha256;
  const _EncryptResult(this.data, this.k, this.iv, this.sha256);
}

/// 在后台 isolate 中初始化 vodozemac 并加密文件。
///
/// 输入明文通过 [TransferableTypedData] 转移所有权（不复制），输出密文
/// 同样零拷贝回传。加密本身复用 matrix 包的 [encryptFile]，保证与
/// SDK 行为完全一致（AES-CTR + SHA-256 + 无填充 base64）。
Future<_EncryptResult> _encryptInIsolate(_EncryptArgs args) async {
  await vod.init(
    wasmPath: './assets/assets/vodozemac/${AppConfig.vodozemacVersion}/',
  );
  final bytes = args.input.materialize().asUint8List();
  final enc = await encryptFile(bytes);
  return _EncryptResult(
    TransferableTypedData.fromList([enc.data]),
    enc.k,
    enc.iv,
    enc.sha256,
  );
}

/// 将大文件加密移到后台 isolate。
///
/// 返回预计算的 [EncryptedFile]，调用方应将其包装进 MatrixFile 子类
/// 并重写 encrypt() 返回它。文件小于 [preEncryptThresholdBytes] 时
/// 返回 null，由调用方走 SDK 默认加密路径。
///
/// 任何异常都向上抛出，由调用方决定是否回退为主 isolate 加密。
Future<EncryptedFile?> encryptFileInBackground(Uint8List bytes) async {
  if (bytes.length < preEncryptThresholdBytes) return null;
  final args = _EncryptArgs(TransferableTypedData.fromList([bytes]));
  final result =
      await Isolate.run<_EncryptResult>(() => _encryptInIsolate(args));
  return EncryptedFile(
    data: result.data.materialize().asUint8List(),
    k: result.k,
    iv: result.iv,
    sha256: result.sha256,
  );
}
