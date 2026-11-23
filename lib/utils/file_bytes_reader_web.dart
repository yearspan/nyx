import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// Web: 没有 isolate，直接用 XFile 读取（浏览器端内存由浏览器管理）。
Future<Uint8List> readFileBytes(String path) =>
    XFile(path).readAsBytes();
