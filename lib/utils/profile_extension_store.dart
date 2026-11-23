import 'package:matrix/matrix.dart';

/// 当前用户扩展资料存储（account_data：com.fluffychat.profile_extension）。
///
/// Matrix 原生 profile 只有 displayname / avatar_url，姓氏与钱包地址
/// 这类扩展字段统一保存在当前用户的 account data 里。
class ProfileExtensionStore {
  static const String type = 'com.fluffychat.profile_extension';

  static Map<String, Object?> _map(Client client) =>
      client.accountData[type]?.content.cast<String, Object?>() ??
      <String, Object?>{};

  static const String keySurname = 'surname';
  static const String keyWalletAddress = 'wallet_address';

  static String? get(Client client, String key) {
    final value = _map(client)[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> set(
    Client client,
    String key,
    String? value,
  ) async {
    final map = Map<String, Object?>.from(_map(client));
    if (value == null || value.trim().isEmpty) {
      map.remove(key);
    } else {
      map[key] = value.trim();
    }
    await client.setAccountData(client.userID!, type, map);
  }
}
