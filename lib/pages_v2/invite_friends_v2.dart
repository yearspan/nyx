import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/qr_code_viewer.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 邀请朋友页面 - 展示个人二维码
class InviteFriendsV2 extends StatefulWidget {
  const InviteFriendsV2({super.key});

  @override
  InviteFriendsV2Controller createState() => InviteFriendsV2Controller();
}

class InviteFriendsV2Controller extends State<InviteFriendsV2> {
  late final Client _client;

  @override
  void initState() {
    super.initState();
    _client = Matrix.of(context).client;
  }

  String get _userLink => 'https://nstalk.space/#/${_client.userID}';

  Future<void> _shareQrCode() async {
    await FluffyShare.share(_userLink, context);
  }

  Future<void> _scanQrCode() async {
    if (!PlatformInfos.isMobile) {
      V2Toast.show(L10n.of(context).scanQrMobileOnly);
      return;
    }
    final result = await context.push<String>('/v2/scan-qr');
    if (result != null && mounted) {
      await _handleScanResult(result);
    }
  }

  /// 处理扫码结果：
  /// - `@user:server`（matrix.to 链接或裸 ID）：发起/复用单聊（即加入联系人）并进入
  /// - `!roomId:server`：加入群聊并进入
  /// - `#alias:server`：解析别名后加入/进入
  Future<void> _handleScanResult(String raw) async {
    final l10n = L10n.of(context);
    final client = _client;
    // parseIdentifierIntoParts 同时支持 matrix.to URL 和裸 matrix ID
    // matrix.to 链接的标识符在 fragment 中（#/!roomId:server），需要多重兜底解析
    final uri = Uri.tryParse(raw);
    final parts = raw.parseIdentifierIntoParts() ??
        (uri?.fragment.isNotEmpty ?? false
            ? uri!.fragment.replaceFirst('/', '').parseIdentifierIntoParts()
            : null) ??
        (uri?.pathSegments.isNotEmpty ?? false
            ? uri!.pathSegments.last.parseIdentifierIntoParts()
            : null);
    final identifier = parts?.primaryIdentifier;
    if (identifier == null) {
      V2Toast.show(l10n.qrScanInvalid);
      return;
    }

    switch (identifier.sigil) {
      case '@':
        if (identifier == client.userID) {
          V2Toast.show(l10n.qrScanIsOwnAccount);
          return;
        }
        // startDirectChat 会写入 m.direct（联系人），已存在单聊时直接返回房间 ID
        final dmResult = await showFutureLoadingDialog(
          context: context,
          future: () => client.startDirectChat(identifier),
        );
        final roomId = dmResult.result;
        if (roomId == null || !mounted) return;
        context.go('/v2/rooms/chat/$roomId');
      case '!':
        final existing = client.getRoomById(identifier);
        if (existing != null) {
          context.go('/v2/rooms/chat/${existing.id}');
          return;
        }
        final joinResult = await showFutureLoadingDialog(
          context: context,
          future: () => _joinAndWait(identifier, parts!.via),
        );
        final roomId = joinResult.result;
        if (roomId == null || !mounted) return;
        context.go('/v2/rooms/chat/$roomId');
      case '#':
        final existing = client.getRoomByAlias(identifier);
        if (existing != null) {
          context.go('/v2/rooms/chat/${existing.id}');
          return;
        }
        final joinResult = await showFutureLoadingDialog(
          context: context,
          future: () async {
            final response = await client.getRoomIdByAlias(identifier);
            final roomId = response.roomId;
            if (roomId == null) {
              throw Exception('Unable to resolve room alias $identifier');
            }
            if (client.getRoomById(roomId) != null) return roomId;
            final via = <String>{
              ...parts!.via,
              ...?response.servers,
            };
            return _joinAndWait(roomId, via);
          },
        );
        final roomId = joinResult.result;
        if (roomId == null || !mounted) return;
        context.go('/v2/rooms/chat/$roomId');
      default:
        V2Toast.show(l10n.qrScanInvalid);
    }
  }

  /// 加入房间并等待首个 /sync 把房间同步下来，避免跳转后找不到房间
  Future<String> _joinAndWait(String roomId, Iterable<String> via) async {
    final viaList = <String>{...via};
    // 房间 ID/别名的域名本身可作为 via 中转
    if (roomId.contains(':')) {
      final domain = roomId.split(':').last;
      if (domain.isNotEmpty) viaList.add(domain);
    }
    // 把用户自己的 homeserver 也加入 via，提高路由成功率
    final userServer = _client.userID?.split(':').sublist(1).join(':');
    if (userServer != null && userServer.isNotEmpty) {
      viaList.add(userServer);
    }
    final joined = await _client.joinRoom(
      roomId,
      via: viaList.isEmpty ? null : viaList.toList(),
    );
    if (_client.getRoomById(joined) == null) {
      await _client.waitForRoomInSync(joined);
    }
    return joined;
  }

  Future<void> _copyUserId() async {
    final l10n = L10n.of(context);
    final userID = _client.userID;
    if (userID == null) return;
    await Clipboard.setData(ClipboardData(text: userID));
    if (!mounted) return;
    V2Toast.show(l10n.copiedToClipboard);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final userID = _client.userID;
    if (userID == null) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final displayName = userID.localpart;
    final textPrimary = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.qrCode),
          Expanded(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          SizedBox(height: 32),
                    // 头像
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: Avatar(
                        client: _client,
                        name: displayName,
                        size: 88,
                      ),
                    ),
                    SizedBox(height: 24),
                    // 二维码卡片（背景始终为白色，保证二维码可扫描）
                    Container(
                      padding: EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: V2Theme.of(context).divider),
                      ),
                      child: GestureDetector(
                        onTap: () => showQrCodeViewer(context, userID),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: PrettyQrView.data(
                            data: _userLink,
                            decoration: const PrettyQrDecoration(
                              shape: PrettyQrSmoothSymbol(
                                roundFactor: 1,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    // 用户 ID（点击复制）
                    GestureDetector(
                      onTap: _copyUserId,
                      child: Text(
                        userID,
                        style: TextStyle(
                          fontSize: 16,
                          color: V2Theme.of(context).accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部按钮区
            Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 分享二维码
                    if (PlatformInfos.isMobile)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _shareQrCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: V2Theme.of(context).accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: Text(
                            l10n.shareQrCode,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(height: 12),
                    // 扫码二维码
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _scanQrCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: V2Theme.of(context).cardBackground,
                          foregroundColor: textPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                            side: BorderSide(color: V2Theme.of(context).divider),
                          ),
                        ),
                        child: Text(
                          l10n.scanQrCode,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
