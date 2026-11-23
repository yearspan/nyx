import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_list_v2/chat_list_v2_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/search/v2_search_mixin.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 聊天列表页（Page）
class ChatListV2 extends StatefulWidget {
  const ChatListV2({super.key});

  @override
  ChatListV2Controller createState() => ChatListV2Controller();
}

class ChatListV2Controller extends State<ChatListV2>
    with TickerProviderStateMixin, RouteAware, V2SearchMixin {
  /// 当前选中的筛选：-1=全部 0=用户 1=未读 2=群聊 3=置顶
  int selectedFilter = -1;

  StreamSubscription? _onSyncUpdate;

  /// 周期性重试卡在「刷新最后事件」占位状态的房间。
  Timer? _placeholderRetryTimer;

  /// 房间当前占位事件的首次发现时间，用于在 SDK 自身请求超时后再重试。
  final Map<String, DateTime> _placeholderSeenSince = {};

  /// 已经过重试的房间：用于区分首次重试（快）与后续重试（慢）。
  final Set<String> _placeholderHasRetried = {};

  /// 正在由本控制器重试刷新的房间，避免重复请求。
  final Set<String> _placeholderRetrying = {};

  /// 本地隐藏的房间（不退房，仅从会话列表移除）。
  /// value 为隐藏时该房间最后一条消息的时间戳，收到更新消息时自动恢复显示。
  static const String _hiddenRoomsKey = 'v2_hidden_rooms';
  final Map<String, int> _hiddenRooms = {};

  @override
  void initState() {
    super.initState();
    _loadHiddenRooms();
    _onSyncUpdate = Matrix.of(context).client.onSync.stream.listen((_) {
      _checkHiddenRoomsOnSync();
      if (mounted) setState(() {});
    });
    _placeholderRetryTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _retryStuckPlaceholders(),
    );
    // 首帧后立即检查一次，避免等满一个扫描周期
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryStuckPlaceholders();
    });
  }

  /// SDK 对没有最后事件的房间只会「发后不管」地请求一次 /messages，
  /// 请求超时或失败后占位事件（显示为「加载中...请等待。」）会一直存在。
  /// 这里周期性地找出卡住的占位并重新刷新。
  Future<void> _retryStuckPlaceholders() async {
    if (!mounted) return;
    final client = Matrix.of(context).client;
    final now = DateTime.now();

    for (final room in client.rooms) {
      final isPlaceholder =
          room.membership == Membership.join &&
          room.lastEvent?.type == EventTypes.refreshingLastEvent;
      if (!isPlaceholder) {
        _placeholderSeenSince.remove(room.id);
        _placeholderHasRetried.remove(room.id);
        continue;
      }
      final seenSince = _placeholderSeenSince.putIfAbsent(room.id, () => now);
      final elapsed = now.difference(seenSince);
      // 首次发现占位立即重试（SDK 的 refreshLastEvent 自带去重，
      // 不会和它自己的请求冲突）；重试失败后每隔 15 秒再试。
      final threshold =
          _placeholderHasRetried.contains(room.id)
              ? const Duration(seconds: 15)
              : Duration.zero;
      if (elapsed < threshold) continue;
      if (_placeholderRetrying.contains(room.id)) continue;

      _placeholderRetrying.add(room.id);
      try {
        await room.refreshLastEvent();
        _placeholderHasRetried.add(room.id);
        // 成功后重置计时，万一刷新结果仍是占位，按长间隔继续重试。
        _placeholderSeenSince[room.id] = DateTime.now();
      } catch (_) {
        // 保留占位记录，下一个周期继续重试。
        _placeholderHasRetried.add(room.id);
        _placeholderSeenSince[room.id] = DateTime.now();
      } finally {
        _placeholderRetrying.remove(room.id);
      }
    }
    if (mounted) setState(() {});
  }

  void _loadHiddenRooms() {
    final raw = Matrix.of(context).store.getString(_hiddenRoomsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _hiddenRooms.addAll(
        map.map((k, v) => MapEntry(k, (v as num).toInt())),
      );
    } catch (_) {}
  }

  Future<void> _persistHiddenRooms() async {
    await Matrix.of(context).store.setString(
      _hiddenRoomsKey,
      jsonEncode(_hiddenRooms),
    );
  }

  /// 把会话从列表删除但不退出房间；收到新消息时会自动恢复显示。
  Future<void> hideRoom(Room room) async {
    _hiddenRooms[room.id] =
        room.lastEvent?.originServerTs.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
    await _persistHiddenRooms();
    if (mounted) setState(() {});
  }

  /// 同步后检查：隐藏的房间若收到新消息则恢复显示
  void _checkHiddenRoomsOnSync() {
    if (_hiddenRooms.isEmpty) return;
    bool changed = false;
    for (final room in Matrix.of(context).client.rooms) {
      final hiddenTs = _hiddenRooms[room.id];
      if (hiddenTs == null) continue;
      final lastTs = room.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (lastTs > hiddenTs) {
        _hiddenRooms.remove(room.id);
        changed = true;
      }
    }
    if (changed) {
      _persistHiddenRooms();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _placeholderRetryTimer?.cancel();
    _onSyncUpdate?.cancel();
    disposeSearch();
    super.dispose();
  }

  /// 获取当前筛选后的房间列表（置顶排最前）
  List<Room> get filteredRooms {
    final allRooms = Matrix.of(context).client.rooms
        .where(
          (r) =>
              !r.isSpace &&
              r.membership != Membership.leave &&
              r.membership != Membership.ban &&
              !_hiddenRooms.containsKey(r.id),
        )
        .toList();

    List<Room> filtered;
    switch (selectedFilter) {
      case 0: // 用户（DM）
        filtered = allRooms.where((r) => r.isDirectChat).toList();
        break;
      case 1: // 未读
        filtered = allRooms.where((r) => r.isUnreadOrInvited).toList();
        break;
      case 2: // 群聊（非私聊）
        filtered = allRooms.where((r) => !r.isDirectChat).toList();
        break;
      case 3: // 置顶
        filtered = allRooms.where((r) => r.isFavourite).toList();
        break;
      default:
        filtered = allRooms;
    }

    // 排序：置顶排最前，其余按最后消息时间降序
    filtered.sort((a, b) {
      final aPin = a.isFavourite ? 0 : 1;
      final bPin = b.isFavourite ? 0 : 1;
      if (aPin != bPin) return aPin.compareTo(bPin);
      final aTs = a.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      final bTs = b.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      return bTs.compareTo(aTs);
    });

    return filtered;
  }

  /// 接受群邀请
  Future<void> acceptInvite(Room room) async {
    await room.join();
    if (!mounted) return;
    setState(() {});
  }

  /// 拒绝群邀请
  Future<void> rejectInvite(Room room) async {
    await room.leave();
    if (!mounted) return;
    setState(() {});
  }

  /// 点击会话
  Future<void> onChatTap(Room room) async {
    if (room.membership == Membership.invite) {
      await acceptInvite(room);
      if (!mounted) return;
    }
    if (room.membership == Membership.ban ||
        room.membership == Membership.leave) {
      return;
    }
    if (!mounted) return;
    // 用 push 压栈而不是 go，保证聊天页可以返回上一页
    context.push('/v2/rooms/chat/${room.id}');
  }

  /// 切换筛选
  void switchFilter(int index) {
    setState(() {
      selectedFilter = index;
    });
  }

  /// 打开新建群聊页
  void openNewGroup() {
    context.push('/v2/create-group');
  }

  /// 邀请朋友 - 跳转到二维码页面
  void shareInvite() {
    context.push('/v2/invite-friends');
  }

  /// 输入地址加入房间
  Future<void> joinByAddress() async {
    final l10n = L10n.of(context);
    final textCtrl = TextEditingController(text: '!:nstalk.space');
    final focusNode = FocusNode();
    final status = ValueNotifier<_JoinStatus>(_JoinStatus.formatValid);

    // 光标定位在 ! 后面
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
      textCtrl.selection = TextSelection(baseOffset: 1, extentOffset: 1);
    });

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: V2Theme.of(context).cardBackground,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 圆形 # 图标
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: V2Theme.of(context).accentLight,
                              shape: BoxShape.circle,
                            ),
                            child: Text("#",style: TextStyle(color: V2Theme.of(context).accent,fontSize: 36),)
                          ),
                        ),
                        SizedBox(height: 16),
                        // 标题
                        Text(
                          l10n.joinRoom,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 20),
                        // 输入框
                        Container(
                          decoration: BoxDecoration(
                            color: V2Theme.of(context).scaffoldBackground,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: V2Theme.of(context).divider),
                          ),
                          child: TextField(
                            controller: textCtrl,
                            focusNode: focusNode,
                            autofocus: true,
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.joinRoomHint,
                              hintStyle: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF8D8D93),
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            onChanged: (value) {
                              setSheet(() {
                                final trimmed = value.trim();
                                if (trimmed.isEmpty) {
                                  status.value = _JoinStatus.idle;
                                } else if (_isValidRoomAddress(trimmed)) {
                                  status.value = _JoinStatus.formatValid;
                                } else {
                                  status.value = _JoinStatus.invalid;
                                }
                              });
                            },
                          ),
                        ),
                        SizedBox(height: 8),
                        // 状态提示
                        ValueListenableBuilder<_JoinStatus>(
                          valueListenable: status,
                          builder: (context, s, _) {
                            if (s == _JoinStatus.invalid) {
                              return Row(
                                children: [
                                  Image.asset(
                                    "assets/images/common/warning.png",
                                    width: 16,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    l10n.joinRoomInvalid,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              );
                            }
                            if (s == _JoinStatus.notFound) {
                              return Row(
                                children: [
                                  Image.asset(
                                    "assets/images/common/warning.png",
                                    width: 16,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    l10n.joinRoomNotFound,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return SizedBox.shrink();
                          },
                        ),
                        SizedBox(height: 10),
                        // 示例提示
                        Text(
                          l10n.joinRoomExample,
                          style: TextStyle(
                            fontSize: 12,
                            color: V2Theme.of(context).textSecondary,
                          ),
                        ),
                        SizedBox(height: 20),
                        // 继续按钮
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed:
                                (status.value == _JoinStatus.formatValid ||
                                    status.value == _JoinStatus.notFound)
                                ? () async {
                                    final address = textCtrl.text.trim();
                                    // 先关闭弹窗
                                    Navigator.pop(context);
                                    // 跳转预览页，预览页负责 resolve + join
                                    this.context.push(
                                      '/v2/join-room/${Uri.encodeComponent(address)}',
                                    );
                                  }
                                : null,
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
                            child: Text(
                              l10n.joinRoomContinue,
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
              ),
            );
          },
        );
      },
    );
  }

  /// 校验 Matrix room 地址格式
  /// 仅接受 !roomId:server 格式（冒号分隔）
  bool _isValidRoomAddress(String input) {
    return input.startsWith('!') && input.contains(':');
  }

  @override
  Widget build(BuildContext context) => ChatListV2View(this);
}

enum _JoinStatus { idle, formatValid, invalid, notFound }
