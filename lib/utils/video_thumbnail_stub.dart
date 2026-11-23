import 'dart:typed_data';

/// Stub implementation used when neither `dart:html` nor `dart:io` is
/// available (e.g. headless test environments). Always returns null.
Future<Uint8List?> extractVideoThumbnail(
  String path,
  Uint8List bytes,
  String mimeType,
) async => null;
