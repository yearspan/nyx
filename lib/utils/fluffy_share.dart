import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/matrix.dart';

abstract class FluffyShare {
  static Future<void> share(
    String text,
    BuildContext context, {
    bool copyOnly = false,
  }) async {
    final l10n = L10n.of(context);
    if (PlatformInfos.isMobile && !copyOnly) {
      final box = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!PlatformInfos.isMobile) {
      V2Toast.show(l10n.copiedToClipboard);
    }
    return;
  }

  static Future<void> shareInviteLink(BuildContext context) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final ownProfile = await client.fetchOwnProfile();
    if (!context.mounted) return;
    await FluffyShare.share(
      l10n.inviteText(
        ownProfile.displayName ?? client.userID!,
        'https://nstalk.space/#/${client.userID}?client=im.nyx',
      ),
      context,
    );
  }
}
