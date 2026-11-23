import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

Future<bool> showTrustUserInRoomDialog(BuildContext context, Room room) async {
  if (!room.encrypted) return true;

  final users = await room.requestParticipants();
  if (!context.mounted) return false;

  users.removeWhere((user) {
    if (user.id == room.client.userID) return true;
    final keys = room.client.userDeviceKeys[user.id];
    final masterKey = keys?.masterKey;

    if (keys == null ||
        masterKey == null ||
        masterKey.verified ||
        masterKey.trustOnFirstUseSince != null) {
      return true;
    }
    return false;
  });

  if (users.isEmpty) return true;

  // 不再弹出"信任用户密钥"对话框：直接按首次使用信任（TOFU）处理，
  // 与原弹窗「继续」按钮的行为一致，避免每次给未验证设备发消息都被打断。
  for (final user in users) {
    room.client.userDeviceKeys[user.id]?.masterKey?.trustOnFirstUse();
  }
  return true;
}
