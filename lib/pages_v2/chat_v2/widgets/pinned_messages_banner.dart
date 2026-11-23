import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 聊天页顶部的置顶消息横幅（仿 Telegram 风格）
///
/// - 有置顶消息时显示在消息列表顶部
/// - 单条：显示发送者 + 内容预览，点击跳转到该消息
/// - 多条：显示「N 条置顶」计数 + 当前一条预览，
///   点击横幅跳转到当前消息并切换到下一条置顶（循环）
/// - 右侧按钮进入置顶消息列表页
class PinnedMessagesBanner extends StatefulWidget {
  final ChatV2Controller controller;

  const PinnedMessagesBanner({super.key, required this.controller});

  @override
  State<PinnedMessagesBanner> createState() => _PinnedMessagesBannerState();
}

class _PinnedMessagesBannerState extends State<PinnedMessagesBanner> {
  Room get room => widget.controller.room;

  /// 当前展示的置顶消息在 pinnedEventIds 中的下标
  int _currentIndex = 0;

  /// 每个事件 id 对应一个稳定的加载 Future，
  /// 避免组件重建时 FutureBuilder 反复回到 loading 状态
  final Map<String, Future<Event?>> _loadFutures = {};

  /// 加载失败 / 超时 / 暂时无法解密的事件 id，
  /// 待 room.onUpdate（密钥到达、解密队列完成）通知后自动重试
  final Set<String> _retryableIds = {};

  /// 各事件最近一次加载时间，用于重试节流，防止高频通知打爆请求
  final Map<String, DateTime> _lastLoadAt = {};

  StreamSubscription<SyncUpdate>? _syncSub;

  /// 单次加载超时：超时后降级为静态文案，保证进度条不会无限播放
  static const _loadTimeout = Duration(seconds: 8);

  /// 同一事件两次加载的最小间隔，避免 sync 高频触发时反复请求
  static const _retryInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _currentIndex = 0;
    // 无法解密的事件在密钥到达后，SDK 会在同一轮 sync 内重新解密完成，
    // onSync 广播时重试即可拿到明文；无待重试事件时处理函数会直接返回
    _syncSub = room.client.onSync.stream.listen((_) => _retryPending());
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  /// 点击横幅：跳转到当前置顶消息，并切换到下一条置顶（循环）
  Future<void> _onBannerTap(List<String> ids) async {
    if (ids.isEmpty) return;
    final targetId = ids[_currentIndex];
    await widget.controller.scrollToEventId(targetId);
    if (!mounted) return;
    // 切换到下一条置顶消息（循环）
    setState(() {
      _currentIndex = (_currentIndex + 1) % ids.length;
    });
  }

  /// 进入置顶消息列表页
  void _openPinnedList() {
    context.push('/v2/rooms/chat/${room.id}/details/pinned');
  }

  /// 清理已取消置顶的事件缓存，避免泄漏与无效重试
  void _evictStaleFutures(List<String> ids) {
    final keep = ids.toSet();
    _loadFutures.removeWhere((id, _) => !keep.contains(id));
    _retryableIds.removeWhere((id) => !keep.contains(id));
    _lastLoadAt.removeWhere((id, _) => !keep.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: room.client.onRoomState.stream
          .where((u) => u.roomId == room.id),
      builder: (context, _) {
        final ids = room.pinnedEventIds;
        if (ids.isEmpty) return SizedBox.shrink();
        // 下标越界保护（取消置顶后列表变短）
        if (_currentIndex >= ids.length) _currentIndex = 0;
        _evictStaleFutures(ids);
        return _buildBanner(context, ids);
      },
    );
  }

  Widget _buildBanner(BuildContext context, List<String> ids) {
    final l10n = L10n.of(context);
    final currentId = ids[_currentIndex];
    final count = ids.length;

    return Material(
      color: V2Theme.of(context).accentLight,
      child: InkWell(
        onTap: () => _onBannerTap(ids),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: V2Theme.of(context).divider, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.push_pin,
                size: 16,
                color: V2Theme.of(context).accent,
              ),
              SizedBox(width: 8),
              Expanded(
                child: FutureBuilder<Event?>(
                  future: _loadEvent(currentId),
                  builder: (context, snapshot) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (count > 1)
                          Text(
                            l10n.pinnedMessagesCount(count),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: V2Theme.of(context).accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        _buildPreviewLine(context, snapshot, l10n),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(width: 8),
              // 多条置顶时显示当前序号
              if (count > 1)
                Text(
                  '${_currentIndex + 1}/$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: V2Theme.of(context).textSecondary,
                  ),
                ),
              if (count > 1) SizedBox(width: 4),
              // 右侧按钮：进入置顶消息列表
              InkWell(
                onTap: _openPinnedList,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: V2Theme.of(context).textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 预览行：
  /// - 加载中：进度条（受 8s 超时约束，不会无限播放）
  /// - 无法解密：固定的解密失败文案
  /// - 加载失败 / 事件不存在：中性降级文案
  /// - 正常：发送者 + 内容预览
  Widget _buildPreviewLine(
    BuildContext context,
    AsyncSnapshot<Event?> snapshot,
    L10n l10n,
  ) {
    final event = snapshot.data;
    final isWaiting =
        snapshot.connectionState != ConnectionState.done && event == null;

    if (isWaiting) {
      return SizedBox(height: 14, child: LinearProgressIndicator());
    }

    final String text;
    if (event != null && _isUndecryptable(event)) {
      text = l10n.messageDecryptionFailed;
    } else if (event != null) {
      text = _buildPreview(event, l10n);
    } else {
      // 加载出错、超时或服务端返回 M_NOT_FOUND
      text = l10n.pinnedMessages;
    }

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  /// 加载置顶事件，同一事件 id 复用同一个 Future
  Future<Event?> _loadEvent(String eventId) {
    final existing = _loadFutures[eventId];
    if (existing != null) return existing;

    _lastLoadAt[eventId] = DateTime.now();
    final future = _doLoadEvent(eventId);
    _loadFutures[eventId] = future;
    return future;
  }

  Future<Event?> _doLoadEvent(String eventId) async {
    try {
      final event = await room.getEventById(eventId).timeout(_loadTimeout);
      if (event == null || _isUndecryptable(event)) {
        // 事件不存在或暂时解不开：标记为可重试，等待密钥到达后自动恢复
        _retryableIds.add(eventId);
        return event;
      }
      _retryableIds.remove(eventId);
      return event;
    } catch (_) {
      _retryableIds.add(eventId);
      return null;
    }
  }

  /// room.onUpdate 通知后，对失败 / 未解密的事件做节流重试
  void _retryPending() {
    if (!mounted || _retryableIds.isEmpty) return;
    final now = DateTime.now();
    final ids = _retryableIds.where((id) {
      final last = _lastLoadAt[id];
      return last == null || now.difference(last) >= _retryInterval;
    }).toList();
    if (ids.isEmpty) return;

    for (final id in ids) {
      _lastLoadAt[id] = now;
      _loadFutures.remove(id);
    }
    setState(() {});
  }

  bool _isUndecryptable(Event event) =>
      event.type == EventTypes.Encrypted ||
      event.messageType == MessageTypes.BadEncrypted;

  String _buildPreview(Event event, L10n l10n) {
    final sender = event.senderFromMemoryOrFallback;
    final body = event
        .calcLocalizedBodyFallback(
          MatrixLocals(l10n),
          hideReply: true,
        )
        .replaceAll('\n', ' ')
        .trim();
    return '${sender.calcDisplayname()}：$body';
  }
}
