import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';

/// V2 风格密钥验证弹窗
///
/// 用于 backup 页面等场景下的设备验证，视觉风格与 [KeyVerificationV2] 一致，
/// 但以 Dialog 形式展示。
class KeyVerificationV2Dialog extends StatefulWidget {
  final KeyVerification request;

  const KeyVerificationV2Dialog({super.key, required this.request});

  /// 以弹窗方式展示验证流程
  Future<bool?> show(BuildContext context) => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => this,
      );

  @override
  State<KeyVerificationV2Dialog> createState() =>
      _KeyVerificationV2DialogState();
}

class _KeyVerificationV2DialogState extends State<KeyVerificationV2Dialog> {
  List<dynamic>? _sasEmoji;
  Profile? _profile;
  bool _busy = false;
  final TextEditingController _ssssController = TextEditingController();

  void Function()? _originalOnUpdate;

  @override
  void initState() {
    super.initState();
    _originalOnUpdate = widget.request.onUpdate;
    widget.request.onUpdate = () {
      _originalOnUpdate?.call();
      if (mounted) setState(() {});
    };
    rootBundle.loadString('assets/sas-emoji.json').then((e) {
      if (mounted) setState(() => _sasEmoji = json.decode(e));
    });
    widget.request.client
        .getProfileFromUserId(widget.request.userId)
        .then((p) {
      if (mounted) setState(() => _profile = p);
    });
  }

  @override
  void dispose() {
    widget.request.onUpdate = _originalOnUpdate;
    if (![KeyVerificationState.error, KeyVerificationState.done]
        .contains(widget.request.state)) {
      widget.request.cancel('m.user');
    }
    _ssssController.dispose();
    super.dispose();
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('[KeyVerificationV2Dialog] action failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitSSSS() async {
    await _runBusy(() async {
      try {
        await widget.request.openSSSS(keyOrPassphrase: _ssssController.text);
      } catch (_) {
        if (mounted) {
          V2Toast.show(L10n.of(context).incorrectPassphraseOrKey);
        }
      }
    });
  }

  String _localizedEmojiName(KeyVerificationEmoji emoji) {
    final sasEmoji = _sasEmoji;
    if (sasEmoji == null) return emoji.name;
    final translations = Map<String, String?>.from(
      sasEmoji[emoji.number]['translated_descriptions'],
    );
    translations['en'] = emoji.name;
    for (final locale in PlatformDispatcher.instance.locales) {
      final wantLocaleParts = locale.toString().split('_');
      final wantLanguage = wantLocaleParts.removeAt(0);
      for (final haveLocale in translations.keys) {
        final haveLocaleParts = haveLocale.split('_');
        final haveLanguage = haveLocaleParts.removeAt(0);
        if (haveLanguage == wantLanguage &&
            (Set.from(haveLocaleParts)..removeAll(wantLocaleParts))
                .isEmpty &&
            (translations[haveLocale]?.isNotEmpty ?? false)) {
          return translations[haveLocale]!;
        }
      }
    }
    return emoji.name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final request = widget.request;

    return Dialog(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(child: _buildBody(request, l10n)),
              SizedBox(height: 16),
              _buildButtons(request, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(KeyVerification request, L10n l10n) {
    switch (request.state) {
      case KeyVerificationState.askSSSS:
        return _buildAskSSSS(l10n);
      case KeyVerificationState.askAccept:
        return _buildAskAccept(request, l10n);
      case KeyVerificationState.askChoice:
      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.waitingSas:
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        return _introView(
          icon: Icons.person_outline,
          title: l10n.waitingOtherUser,
          body: l10n.waitingOtherUserBody,
          loading: true,
        );
      case KeyVerificationState.askSas:
        return _buildEmojiCompare(request, l10n);
      case KeyVerificationState.done:
        return _introView(
          icon: Icons.check,
          iconColor: Color(0xFF34C759),
          title: l10n.verificationSuccessTitle,
          body: l10n.verificationSuccessBody,
        );
      case KeyVerificationState.error:
        return _introView(
          icon: Icons.priority_high,
          iconColor: Color(0xFFFF3B30),
          title: l10n.verificationFailedTitle,
          body: l10n.verificationFailedBody,
        );
    }
  }

  /// 居中的图标 + 标题 + 说明
  Widget _introView({
    required IconData icon,
    required String title,
    required String body,
    Color? iconColor,
    bool loading = false,
  }) {
    return ListView(
      shrinkWrap: true,
      children: [
        SizedBox(height: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: iconColor ?? V2Theme.of(context).accent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: Colors.white),
            ),
            if (loading)
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
      ],
    );
  }

  /// 接收方：对方信息卡片 + 说明
  Widget _buildAskAccept(KeyVerification request, L10n l10n) {
    final userId = request.userId;
    final roomId =
        request.client.getDirectChatFromUserId(userId);
    final user = roomId != null
        ? request.client
            .getRoomById(roomId)
            ?.unsafeGetUserFromMemoryOrFallback(userId)
        : null;
    final displayName =
        _profile?.displayName ?? user?.calcDisplayname() ?? userId.localpart!;

    return ListView(
      shrinkWrap: true,
      children: [
        SizedBox(height: 8),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: V2Theme.of(context).accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person_outline, size: 36, color: Colors.white),
        ),
        SizedBox(height: 20),
        Text(
          l10n.verifyRequestTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 10),
        Text(
          l10n.verifyRequestBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
        SizedBox(height: 20),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Avatar(
                mxContent: _profile?.avatarUrl ?? user?.avatarUrl,
                name: displayName,
                size: 40,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '@${userId.localpart}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// emoji 七格 + 说明
  Widget _buildEmojiCompare(KeyVerification request, L10n l10n) {
    final emojis = request.sasEmojis;
    return ListView(
      shrinkWrap: true,
      children: [
        SizedBox(height: 8),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: V2Theme.of(context).accent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sentiment_satisfied_outlined,
            size: 36,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 20),
        Text(
          l10n.compareEmoji,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 10),
        Text(
          l10n.compareEmojiSameBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
        SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 16,
          children: [
            for (final e in emojis)
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: V2Theme.of(context).cardBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(e.emoji, style: TextStyle(fontSize: 26)),
                    ),
                    SizedBox(height: 6),
                    Text(
                      _localizedEmojiName(e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 安全密钥/恢复密码输入
  Widget _buildAskSSSS(L10n l10n) {
    return ListView(
      shrinkWrap: true,
      children: [
        SizedBox(height: 8),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: V2Theme.of(context).accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.lock_outline, size: 36, color: Colors.white),
        ),
        SizedBox(height: 20),
        Text(
          l10n.askSSSSSign,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ssssController,
            autocorrect: false,
            obscureText: true,
            onSubmitted: (_) => _submitSSSS(),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: l10n.passphraseOrKey,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(KeyVerification request, L10n l10n) {
    final children = <Widget>[];

    switch (request.state) {
      case KeyVerificationState.askSSSS:
        children.add(_primaryButton(
          label: l10n.submit,
          onTap: _busy ? null : _submitSSSS,
        ));
        children.add(SizedBox(height: 10));
        children.add(_secondaryButton(
          label: l10n.skip,
          onTap: _busy
              ? null
              : () => _runBusy(() => request.openSSSS(skip: true)),
        ));
        break;
      case KeyVerificationState.askAccept:
        children.add(_primaryButton(
          label: _busy ? '${l10n.verifyStart}...' : l10n.verifyStart,
          onTap: _busy ? null : () => _runBusy(request.acceptVerification),
        ));
        children.add(SizedBox(height: 10));
        children.add(_secondaryButton(
          label: l10n.ignore,
          onTap: _busy
              ? null
              : () => _runBusy(() async {
                    await request.rejectVerification();
                    if (mounted) Navigator.of(context).pop(false);
                  }),
        ));
        break;
      case KeyVerificationState.askChoice:
      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.waitingSas:
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        children.add(_secondaryButton(
          label: l10n.cancel,
          onTap: _busy ? null : () => _runBusy(request.cancel),
        ));
        break;
      case KeyVerificationState.askSas:
        children.add(_primaryButton(
          label: l10n.theyMatch,
          onTap: _busy ? null : () => _runBusy(request.acceptSas),
        ));
        children.add(SizedBox(height: 10));
        children.add(_secondaryButton(
          label: l10n.theyDontMatch,
          onTap: _busy ? null : () => _runBusy(request.rejectSas),
        ));
        break;
      case KeyVerificationState.done:
        children.add(_primaryButton(
          label: l10n.done,
          onTap: () => Navigator.of(context).pop(true),
        ));
        break;
      case KeyVerificationState.error:
        children.add(_primaryButton(
          label: l10n.close,
          onTap: () => Navigator.of(context).pop(false),
        ));
        break;
    }

    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: V2Theme.of(context).accent,
          disabledBackgroundColor:
              V2Theme.of(context).accent.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: V2Theme.of(context).cardBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
