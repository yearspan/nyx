import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/pulsating_widget.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class IncomingCallDialog extends StatefulWidget {
  final Event event;
  const IncomingCallDialog({required this.event, super.key});

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog> {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription? _onSync;

  @override
  void initState() {
    _initAudioPlayer();
    _onSync = widget.event.room.client.onSync.stream.listen((_) {
      if (!mounted) return;
      if (!widget.event.room.hasActiveMatrixRtcCall) {
        Logs().i('The other party has ended the call');
        Navigator.of(context).pop();
      } else if (widget.event.room.getActiveMatrixRtcMembers().any(
        (member) =>
            member.senderId == widget.event.room.client.userID! &&
            member.deviceId != widget.event.room.client.deviceID!,
      )) {
        Logs().i('User has accepted the call on a different device');
        Navigator.of(context).pop();
      }
    });
    final timeout =
        widget.event.tryParseRtcNotificationContent()?.lifetime ??
        RtcNotificationContent.defaultLifetime;
    Future.delayed(timeout).then((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    });
    super.initState();
  }

  Future<void> _initAudioPlayer() async {
    await _player.setAsset('assets/sounds/call_ring.mp3');
    await _player.setLoopMode(.one);
    await _player.play();
  }

  @override
  void dispose() {
    _onSync?.cancel();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  /// 被叫方拒绝接听：发送拒绝通知给主叫方，然后关闭弹窗。
  ///
  /// 与移动端 IncomingCallPage 共用 sendCallRejectNotification 逻辑，
  /// 否则主叫方收不到拒绝事件，会一直停留在"呼叫中"直到振铃超时。
  Future<void> _reject() async {
    try {
      await widget.event.room.sendCallRejectNotification();
    } catch (e, s) {
      Logs().w('Failed to send call reject notification', e, s);
    }
    if (!mounted) return;
    context.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final displayname = widget.event.room.getLocalizedDisplayname();
    final avatar = widget.event.room.avatar;
    final theme = Theme.of(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Center(child: Text(L10n.of(context).incomingCall)),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: .min,
          spacing: 8,
          children: [
            PulsatingWidget(
              spreadRadius: 10.0,
              color: theme.colorScheme.primary,
              child: Avatar(mxContent: avatar, name: displayname),
            ),
            Text(displayname, textAlign: .center),
          ],
        ),
      ),
      actionsAlignment: .spaceEvenly,
      actions: [
        IconButton(
          style: IconButton.styleFrom(
            fixedSize: Size.fromRadius(24),
            elevation: theme.appBarTheme.elevation ?? 4,
            shadowColor: theme.appBarTheme.shadowColor,
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          icon: Icon(Icons.call_end_outlined),
          onPressed: _reject,
        ),
        IconButton(
          style: IconButton.styleFrom(
            fixedSize: Size.fromRadius(24),
            elevation: theme.appBarTheme.elevation ?? 4,
            shadowColor: theme.appBarTheme.shadowColor,
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
          ),
          icon: Icon(Icons.call_outlined),
          onPressed: () => context.pop(true),
        ),
      ],
    );
  }
}
