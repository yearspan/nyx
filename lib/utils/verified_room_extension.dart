import 'package:matrix/matrix.dart';

extension VerifiedRoomExtension on Room {
  bool get allUsersVerified {
    final users = getParticipants();
    return !users.any(
      (user) => client.userDeviceKeys[user.id]?.masterKey?.verified != true,
    );
  }
}
