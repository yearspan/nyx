import 'package:matrix/matrix.dart';

import 'file_encryptor_stub.dart'
    if (dart.library.html) 'file_encryptor_web.dart'
    if (dart.library.io) 'file_encryptor_native.dart';

/// MatrixFile 子类，重写 [encrypt] 将大文件加密移到后台 isolate。
///
/// 关键：不预加密。用 [wrapWithBackgroundEncryption] 包装后直接传给
/// `room.sendFileEvent`。SDK 内部流程是先创建占位事件（用户立即看到
/// 消息出现在聊天里），再调用 `file.encrypt()`；此时本类的 encrypt()
/// 把加密派发到后台 isolate，主 isolate 不阻塞，占位符保持响应。
///
/// 小于阈值的文件 [encryptFileInBackground] 返回 null，回退到主线程
/// `encryptFile`（耗时可忽略），与原 SDK 行为一致。
///
/// 图片不使用本包装：SDK 会 shrink 并替换为新实例，且 shrink 后体积小。
class BackgroundEncryptedMatrixFile extends MatrixFile {
  BackgroundEncryptedMatrixFile({
    required super.bytes,
    required super.name,
    super.mimeType,
  });

  @override
  Future<EncryptedFile> encrypt() async {
    final enc = await encryptFileInBackground(bytes);
    if (enc != null) return enc;
    return await encryptFile(bytes);
  }
}

class BackgroundEncryptedMatrixImageFile extends MatrixImageFile {
  BackgroundEncryptedMatrixImageFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    super.width,
    super.height,
    super.blurhash,
  });

  @override
  Future<EncryptedFile> encrypt() async {
    final enc = await encryptFileInBackground(bytes);
    if (enc != null) return enc;
    return await encryptFile(bytes);
  }
}

class BackgroundEncryptedMatrixVideoFile extends MatrixVideoFile {
  BackgroundEncryptedMatrixVideoFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    super.width,
    super.height,
    super.duration,
  });

  @override
  Future<EncryptedFile> encrypt() async {
    final enc = await encryptFileInBackground(bytes);
    if (enc != null) return enc;
    return await encryptFile(bytes);
  }
}

class BackgroundEncryptedMatrixAudioFile extends MatrixAudioFile {
  BackgroundEncryptedMatrixAudioFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    super.duration,
  });

  @override
  Future<EncryptedFile> encrypt() async {
    final enc = await encryptFileInBackground(bytes);
    if (enc != null) return enc;
    return await encryptFile(bytes);
  }
}

/// 按运行时类型把原始 MatrixFile 包装为后台加密子类。
///
/// 包装后直接传给 sendFileEvent；SDK 先建占位事件，再异步调用
/// encrypt() 时加密在后台 isolate 执行。
MatrixFile wrapWithBackgroundEncryption(MatrixFile source) {
  if (source is MatrixImageFile) {
    return BackgroundEncryptedMatrixImageFile(
      bytes: source.bytes,
      name: source.name,
      mimeType: source.mimeType,
      width: source.width,
      height: source.height,
      blurhash: source.blurhash,
    );
  }
  if (source is MatrixVideoFile) {
    return BackgroundEncryptedMatrixVideoFile(
      bytes: source.bytes,
      name: source.name,
      mimeType: source.mimeType,
      width: source.width,
      height: source.height,
      duration: source.duration,
    );
  }
  if (source is MatrixAudioFile) {
    return BackgroundEncryptedMatrixAudioFile(
      bytes: source.bytes,
      name: source.name,
      mimeType: source.mimeType,
      duration: source.duration,
    );
  }
  return BackgroundEncryptedMatrixFile(
    bytes: source.bytes,
    name: source.name,
    mimeType: source.mimeType,
  );
}
