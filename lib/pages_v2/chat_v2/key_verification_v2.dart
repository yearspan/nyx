import 'dart:convert';
import 'dart:ui';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// V2 用户密钥验证页（SAS emoji）
///
/// 两种入口：
/// - 发起方：从个人资料页进入，仅传 [roomId]，点击「开始验证」后才创建请求；
/// - 接收方：全局监听收到对方请求，直接传入已存在的 [existingRequest]。
class KeyVerificationV2 extends StatefulWidget {
  /// 发起方入口：私聊房间 id
  final String? roomId;

  /// 接收方入口：已存在的验证请求
  final KeyVerification? existingRequest;

  const KeyVerificationV2({super.key, this.roomId, this.existingRequest});

  @override
  State<KeyVerificationV2> createState() => _KeyVerificationV2State();
}

class _KeyVerificationV2State extends State<KeyVerificationV2> {
  KeyVerification? _request;
  List<dynamic>? _sasEmoji;
  Profile? _profile;

  /// 发起方是否已点击「开始验证」并创建请求
  bool _started = false;

  bool _busy = false;
  final TextEditingController _ssssController = TextEditingController();

  Client get client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/sas-emoji.json').then((e) {
      if (mounted) {
        setState(() => _sasEmoji = json.decode(e));
      }
    });
    if (widget.existingRequest != null) {
      _attach(widget.existingRequest!);
      _started = true;
      _loadProfile(widget.existingRequest!.userId);
    }
  }

  @override
  void dispose() {
    _ssssController.dispose();
    final request = _request;
    if (request != null &&
        ![KeyVerificationState.error, KeyVerificationState.done]
            .contains(request.state)) {
      request.cancel('m.user');
    }
    super.dispose();
  }

  void _attach(KeyVerification request) {
    _request = request;
    request.onUpdate = () {
      if (mounted) setState(() {});
    };
    _loadProfile(request.userId);
  }

  void _loadProfile(String userId) {
    client.getProfileFromUserId(userId).then((p) {
      if (mounted) setState(() => _profile = p);
    });
  }

  /// 发起方：创建验证请求
  Future<void> _startVerification() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room =
          widget.roomId != null ? client.getRoomById(widget.roomId!) : null;
      final userId = room?.directChatMatrixID ?? _request?.userId;
      final request = await client.userDeviceKeys[userId]?.startVerification();
      if (request == null) return;
      _attach(request);
      if (mounted) setState(() => _started = true);
    } catch (e) {
      debugPrint('[KeyVerificationV2] start failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('[KeyVerificationV2] action failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pop() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/v2/rooms');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.verifyUser,
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              onBack: _pop,
            ),
            Expanded(child: _buildBody(l10n)),
            _buildBottomBar(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(L10n l10n) {
    final request = _request;

    // 发起方介绍页
    if (!_started || request == null) {
      return _introView(
        icon: Icons.lock_outline,
        title: l10n.verifyThisUser,
        body: l10n.verifyThisUserBody,
      );
    }

    switch (request.state) {
      case KeyVerificationState.askSSSS:
        return _buildAskSSSS(l10n);
      case KeyVerificationState.askAccept:
        // 接收方：验证请求
        return _buildAskAccept(request, l10n);
      case KeyVerificationState.askChoice:
      case KeyVerificationState.waitingAccept:
        return _introView(
          icon: Icons.person_outline,
          title: l10n.waitingOtherUser,
          body: l10n.waitingOtherUserBody,
          loading: true,
        );
      case KeyVerificationState.askSas:
        return _buildEmojiCompare(request, l10n);
      case KeyVerificationState.waitingSas:
        return _introView(
          icon: Icons.person_outline,
          title: l10n.waitingOtherUser,
          body: l10n.waitingOtherUserBody,
          loading: true,
        );
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        return _introView(
          icon: Icons.person_outline,
          title: l10n.waitingOtherUser,
          body: l10n.waitingOtherUserBody,
          loading: true,
        );
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
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        SizedBox(height: 24),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: iconColor ?? V2Theme.of(context).accent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: Colors.white),
            ),
            if (loading)
              SizedBox(
                width: 104,
                height: 104,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
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
    final roomId = client.getDirectChatFromUserId(userId);
    final user = roomId != null
        ? client
            .getRoomById(roomId)
            ?.unsafeGetUserFromMemoryOrFallback(userId)
        : null;
    final displayName =
        _profile?.displayName ?? user?.calcDisplayname() ?? userId.localpart!;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        SizedBox(height: 24),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: V2Theme.of(context).accent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_outline,
            size: 48,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 24),
        Text(
          l10n.verifyRequestTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 12),
        Text(
          l10n.verifyRequestBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
        SizedBox(height: 24),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Avatar(
                mxContent: _profile?.avatarUrl ?? user?.avatarUrl,
                name: displayName,
                size: 44,
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
                        fontSize: 16,
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
                        fontSize: 13,
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
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        SizedBox(height: 24),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: V2Theme.of(context).accent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sentiment_satisfied_outlined,
            size: 48,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 24),
        Text(
          l10n.compareEmoji,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 12),
        Text(
          l10n.compareEmojiSameBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
        SizedBox(height: 32),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 20,
            children: [
              for (final e in emojis)
                SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: V2Theme.of(context).cardBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          e.emoji,
                          style: TextStyle(fontSize: 30),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        _localizedEmojiName(e),
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

  /// 安全密钥/恢复密码输入（签名对方设备时需要）
  Widget _buildAskSSSS(L10n l10n) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        SizedBox(height: 24),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: V2Theme.of(context).accent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.lock_outline,
            size: 48,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 24),
        Text(
          l10n.askSSSSSign,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 20),
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

  Future<void> _submitSSSS() async {
    final request = _request;
    if (request == null) return;
    await _runBusy(() async {
      try {
        await request.openSSSS(keyOrPassphrase: _ssssController.text);
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
            (Set.from(haveLocaleParts)..removeAll(wantLocaleParts)).isEmpty &&
            (translations[haveLocale]?.isNotEmpty ?? false)) {
          return translations[haveLocale]!;
        }
      }
    }
    return emoji.name;
  }

  Widget _buildBottomBar(L10n l10n) {
    final request = _request;
    final children = <Widget>[];

    if (!_started || request == null) {
      // 发起方介绍页
      children.add(
        _primaryButton(
          label: l10n.verifyStart,
          onTap: _startVerification,
        ),
      );
    } else {
      switch (request.state) {
        case KeyVerificationState.askSSSS:
          children.add(
            _primaryButton(
              label: l10n.submit,
              onTap: _submitSSSS,
            ),
          );
          children.add(SizedBox(height: 12));
          children.add(
            _secondaryButton(
              label: l10n.skip,
              onTap: () => _runBusy(
                () => request.openSSSS(skip: true),
              ),
            ),
          );
          break;
        case KeyVerificationState.askAccept:
          // 接收方：开始验证 / 忽视
          children.add(
            _primaryButton(
              label: _busy ? '${l10n.verifyStart}...' : l10n.verifyStart,
              onTap: _busy
                  ? null
                  : () => _runBusy(request.acceptVerification),
            ),
          );
          children.add(SizedBox(height: 12));
          children.add(
            _secondaryButton(
              label: l10n.ignore,
              onTap: () => _runBusy(() async {
                await request.rejectVerification();
                _pop();
              }),
            ),
          );
          break;
        case KeyVerificationState.askChoice:
        case KeyVerificationState.waitingAccept:
        case KeyVerificationState.waitingSas:
        case KeyVerificationState.showQRSuccess:
        case KeyVerificationState.confirmQRScan:
          children.add(
            _secondaryButton(
              label: l10n.cancel,
              onTap: _busy ? null : () => _runBusy(request.cancel),
            ),
          );
          break;
        case KeyVerificationState.askSas:
          children.add(
            _primaryButton(
              label: l10n.theyMatch,
              onTap: _busy
                  ? null
                  : () => _runBusy(request.acceptSas),
            ),
          );
          children.add(SizedBox(height: 12));
          children.add(
            _secondaryButton(
              label: l10n.theyDontMatch,
              onTap: _busy
                  ? null
                  : () => _runBusy(request.rejectSas),
            ),
          );
          break;
        case KeyVerificationState.done:
          children.add(
            _primaryButton(label: l10n.done, onTap: _pop),
          );
          break;
        case KeyVerificationState.error:
          children.add(
            _primaryButton(label: l10n.retry, onTap: _pop),
          );
          break;
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: V2Theme.of(context).accent,
          disabledBackgroundColor: V2Theme.of(context).accent.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
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
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: V2Theme.of(context).cardBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
