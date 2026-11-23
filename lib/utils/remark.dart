import 'package:matrix/matrix.dart';

/// 本地备注存储：使用全局 account_data（com.fluffychat.remarks），
/// 内容为 { matrixId: 备注字符串 }，仅本地生效，不改变房间名。
class RemarkStore {
  static const String type = 'com.fluffychat.remarks';

  static Map<String, Object?> _remarksMap(Client client) =>
      client.accountData[type]?.content.cast<String, Object?>() ??
      <String, Object?>{};

  /// 读取某个用户的备注，未设置返回 null
  static String? getRemark(Client client, String matrixId) {
    final value = _remarksMap(client)[matrixId];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 写入 / 清除某个用户的备注（remark 为 null 或空字符串则清除）
  static Future<void> setRemark(
    Client client,
    String matrixId,
    String? remark,
  ) async {
    final map = Map<String, Object?>.from(_remarksMap(client));
    if (remark == null || remark.trim().isEmpty) {
      map.remove(matrixId);
    } else {
      map[matrixId] = remark.trim();
    }
    await client.setAccountData(client.userID!, type, map);
  }
}
