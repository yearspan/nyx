import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// 加入聊天室预览页
class JoinRoomPreviewV2 extends StatefulWidget {
  final String address;
  const JoinRoomPreviewV2({super.key, required this.address});

  @override
  JoinRoomPreviewV2Controller createState() => JoinRoomPreviewV2Controller();
}

class JoinRoomPreviewV2Controller extends State<JoinRoomPreviewV2> {
  bool _loading = true;
  bool _joining = false;
  String? _roomName;
  String? _avatarUrl;
  int? _memberCount;
  String? _topic;
  String? _resolvedRoomId;
  String? _error;
  bool _isInRoom = false;

  @override
  void initState() {
    super.initState();
    _resolveRoom();
  }

  Future<void> _resolveRoom() async {
    try {
      final client = Matrix.of(context).client;
      final address = widget.address; // 必然是 !xxx:server 格式

      // 只查 roomId
      final room = client.getRoomById(address);
      if (room != null) {
        _resolvedRoomId = room.id;
        _roomName = room.getLocalizedDisplayname();
        _avatarUrl = room.avatar.toString();
        _memberCount = room.summary.mJoinedMemberCount;
        _topic = room.topic;
        _isInRoom = room.membership == Membership.join;
      } else {
        _resolvedRoomId = address;
        _roomName = address;
        _isInRoom = false;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _roomName = widget.address;
      });
    }
  }

  /// 从 roomId 或 alias 中提取 server name 作为 via 中转服务器
  List<String>? _extractVia(String roomIdOrAlias) {
    final parts = roomIdOrAlias.split(':');
    if (parts.length >= 2) {
      final server = parts.sublist(1).join(':');
      return server.isNotEmpty ? [server] : null;
    }
    return null;
  }

  Future<void> _applyJoin() async {
    if (_isInRoom) {
      context.go('/v2/rooms/chat/$_resolvedRoomId');
      return;
    }
    setState(() => _joining = true);
    try {
      final client = Matrix.of(context).client;
      final via = _extractVia(_resolvedRoomId!);
      final userServer = client.userID?.split(':').sublist(1).join(':');
      // 把用户自己的 homeserver 也加进 via 列表，提高路由成功率
      final combinedVia = <String>{};
      if (via != null) combinedVia.addAll(via);
      if (userServer != null) combinedVia.add(userServer);
      final viaList = combinedVia.isEmpty ? null : combinedVia.toList();
      Logs().w(
        'joinRoom 参数: roomId=$_resolvedRoomId, via=$viaList, userServer=$userServer',
      );
      final roomId = await client.joinRoom(_resolvedRoomId!, via: viaList);
      if (client.getRoomById(roomId) == null) {
        await client.waitForRoomInSync(roomId);
      }
      if (!mounted) return;
      context.go('/v2/rooms/chat/$roomId');
    } catch (e, s) {
      Logs().w('joinRoom 失败: $e\n$s');
      if (!mounted) return;
      setState(() => _joining = false);
      await showOkAlertDialog(
        context: context,
        title: L10n.of(context).joinRoomFailed,
        message: e.toString(),
      );
    }
  }

  /// 根据房间名生成一个固定颜色
  Color _avatarColor(String name) {
    final colors = [
      Color(0xFF7C5CFC), // purple
      Color(0xFF3DD9D9), // teal
      Color(0xFFFF7A59), // coral
      Color(0xFFFFB020), // amber
      Color(0xFF4B9BFF), // blue
      Color(0xFF2BD97B), // green
    ];
    int hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayName = _roomName ?? widget.address;
    final avatarColor = _avatarColor(displayName);
    final memberText = _memberCount != null
        ? l10n.membersCount(_memberCount!)
        : l10n.membersCount(1);

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          const V2AppBar(),
          Expanded(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // 可滚动区
                  Expanded(
              child: _error != null && !_loading
                  // 错误状态：房间未找到
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: V2Theme.of(context).divider,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.search_off,
                              size: 36,
                              color: V2Theme.of(context).textSecondary,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            l10n.joinRoomNotFound,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            widget.address,
                            style: TextStyle(
                              fontSize: 14,
                              color: V2Theme.of(context).textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  // 正常状态
                  : ListView(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        SizedBox(height: 32),
                        // 大圆形头像
                        Center(
                          child: _loading
                              ? Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: avatarColor.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(36),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: avatarColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: _avatarUrl != null
                                      ? ClipOval(
                                          child: Image.network(
                                            _avatarUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.person,
                                              size: 56,
                                              color: Colors.white.withOpacity(
                                                0.5,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Icon(
                                          Icons.person,
                                          size: 56,
                                          color: Colors.white.withOpacity(0.5),
                                        ),
                                ),
                        ),
                        SizedBox(height: 20),
                        // 房间名
                        Text(
                          _loading ? '' : displayName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        // 成员数
                        Text(
                          _loading ? '' : memberText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: V2Theme.of(context).textSecondary,
                          ),
                        ),
                        SizedBox(height: 28),
                        // 简介卡片
                        Container(
                          decoration: BoxDecoration(
                            color: V2Theme.of(context).cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: V2Theme.of(context).divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  6,
                                ),
                                child: Text(
                                  l10n.joinRoomIntro,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 1,
                                child: ColoredBox(color: V2Theme.of(context).divider),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  14,
                                ),
                                child: Text(
                                  (_topic != null && _topic!.isNotEmpty)
                                      ? _topic!
                                      : l10n.joinRoomNoTopic,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: V2Theme.of(context).textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            // 底部申请加入按钮（错误状态隐藏）
            if (_error == null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading || _joining ? null : _applyJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: V2Theme.of(context).accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: V2Theme.of(context).divider,
                        disabledForegroundColor: Colors.white54,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: _joining
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isInRoom
                                  ? l10n.joinRoomEnter
                                  : l10n.joinRoomApply,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
    );
  }
}
