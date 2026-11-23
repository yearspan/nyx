import 'package:material_ui/material_ui.dart';

import 'package:matrix/matrix.dart';

IconData _getIconFromName(String displayname) {
  final name = displayname.toLowerCase();
  if ({'android', 'ios', 'ipad', 'iphone', 'ipod'}.any(name.contains)) {
    return Icons.smartphone_outlined;
  }
  return Icons.laptop_outlined;
}

IconData _getIconDataFromName(String displayname) {
  final name = displayname.toLowerCase();
  if ({'android', 'ios', 'ipad', 'iphone', 'ipod'}.any(name.contains)) {
    return Icons.smartphone_outlined;
  }
  return Icons.laptop_outlined;
}

extension DeviceExtension on Device {
  String get displayname =>
      (displayName?.isNotEmpty ?? false) ? displayName! : 'Unknown device';

  IconData get icon => _getIconFromName(displayname);

  IconData get iconData => _getIconDataFromName(displayname);
}

extension DeviceKeysExtension on DeviceKeys {
  String get displayname => (deviceDisplayName?.isNotEmpty ?? false)
      ? deviceDisplayName!
      : 'Unknown device';

  IconData get icon => _getIconFromName(displayname);

  IconData get iconData => _getIconDataFromName(displayname);
}
