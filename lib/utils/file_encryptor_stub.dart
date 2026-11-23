import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// 占位实现：返回 null，由调用方走 SDK 默认加密路径。
Future<EncryptedFile?> encryptFileInBackground(Uint8List bytes) async => null;
