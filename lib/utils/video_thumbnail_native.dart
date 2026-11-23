import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Native (macOS/Linux/Windows): use media_kit's mpv backend to decode the
/// first frame via `screenshot()`.
///
/// mpv's `screenshot-raw` needs a decoded frame, which requires a render
/// context. `VideoController` sets `vo=libmpv` and creates the render context
/// (texture) so frames get decoded.
Future<Uint8List?> extractVideoThumbnail(
  String path,
  Uint8List bytes,
  String mimeType,
) async {
  Player? player;
  VideoController? controller;
  try {
    player = Player();
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        width: 320,
        height: 320,
      ),
    );
    await controller.platform.future;

    // 取帧时需要短暂播放以触发帧解码，先静音避免发出声音。
    await player.setVolume(0);

    await player.open(Media(path), play: true);
    await player.seek(Duration.zero);

    // open()/seek() return after issuing the command; the first frame is
    // decoded asynchronously. Poll screenshot() with a bounded retry loop.
    Uint8List? bytes;
    const maxAttempts = 30;
    for (var i = 0; i < maxAttempts; i++) {
      final shot = await player.screenshot();
      if (shot != null && shot.isNotEmpty) {
        bytes = shot;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    await player.pause();
    return bytes;
  } catch (_) {
    return null;
  } finally {
    // VideoController registers its cleanup on player.platform.release,
    // so disposing the player tears down the render context too.
    await player?.dispose();
  }
}
