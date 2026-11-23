import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Native: 大文件 readAsBytes 会在主 isolate 分配巨大 byte 数组导致
/// UI 卡顿 / ANR，放到后台 isolate 读取。
///
/// 使用 [TransferableTypedData] 而非直接返回 Uint8List：普通 isolate
/// 消息传递会把字节数组完整复制一份到主 isolate，大文件时峰值内存
/// 翻倍触发 Android OOM。TransferableTypedData 是内存所有权转移
/// （零拷贝），后台 isolate 读取后立即移交，不产生副本。
Future<Uint8List> readFileBytes(String path) async {
  final transferable = await Isolate.run<TransferableTypedData>(
    () async =>
        TransferableTypedData.fromList([await File(path).readAsBytes()]),
  );
  return transferable.materialize().asUint8List();
}
