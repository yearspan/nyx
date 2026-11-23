import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2_view.dart';
import 'package:fluffychat/pages_v2/chat_v2/send_file_dialog.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/pre_encrypted_matrix_file.dart';
import 'package:fluffychat/utils/translation.dart';
import 'package:fluffychat/utils/translation_store.dart';
import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide RequestType;
import 'package:mime/mime.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// V2 聊天页（Page）
class ChatV2 extends StatefulWidget {
  final String roomId;
  final List<ShareItem>? shareItems;

  /// 进入聊天后自动滚动定位到的事件 ID（搜索结果跳转等场景使用）
  final String? eventId;

  /// 进入聊天后自动执行的动作，目前支持 'call'（点击通话通知后自动发起呼叫）
  final String? action;

  const ChatV2({
    super.key,
    required this.roomId,
    this.shareItems,
    this.eventId,
    this.action,
  });

  @override
  ChatV2Controller createState() => ChatV2Controller();
}

class ChatV2Controller extends State<ChatV2> with WidgetsBindingObserver {
  Room? _room;
  // 可为空的房间，用于视图在房间尚未加载时安全地显示加载态
  Room? get roomOrNull => sendingClient.getRoomById(roomId) ?? _room;
  Room get room => roomOrNull!;
  late Client sendingClient;
  Timeline? timeline;

  final AutoScrollController scrollController = AutoScrollController();
  late final FocusNode inputFocus;
  final TextEditingController sendController = TextEditingController();
  final GlobalKey inputBarKey = GlobalKey();

  Event? replyEvent;
  Event? editEvent;
  bool _scrolledUp = false;
  bool _inputTextIsEmpty = true;
  bool get inputTextIsEmpty => _inputTextIsEmpty;

  // 多选模式（长按菜单中的"选择"进入）
  final Set<Event> selectedEvents = {};
  bool get isSelecting => selectedEvents.isNotEmpty;

  String get roomId => widget.roomId;

  /// 服务器是否提供 MatrixRTC/LiveKit 通话服务
  bool supportsCalls = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  StreamSubscription? _onSyncUpdate;

  /// 当前需要高亮闪烁的消息 ID（点击置顶消息跳转后短暂高亮）
  String? highlightEventId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    inputFocus = FocusNode();
    scrollController.addListener(_updateScrollController);
    WidgetsBinding.instance.addObserver(this);
    sendingClient = Matrix.of(context).client;
    // 标记当前正在浏览的房间，供被踢出群时判断是否退回主页
    MatrixState.currentViewingRoomId = room.id;
    _loadTimeline();
    _loadDraft();
    // 预加载本地翻译缓存，历史消息的译文能立即显示
    unawaited(TranslationStore.instance.get(''));
    // 启用自动删除（max_lifetime）时，每分钟刷新一次界面，
    // 让跨过截止时间的消息自动消失。
    _retentionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (retentionMaxLifetime != null) updateView();
    });
  }

  Future<void> _loadTimeline() async {
    final matrix = Matrix.of(context);
    // 聊天列表能点进来说明房间对象已在内存中，直接取用，
    // 避免冷启动时阻塞在数据库加载等待上
    _room = matrix.client.getRoomById(roomId);
    if (_room == null) {
      await matrix.client.roomsLoading;
      await matrix.client.accountDataLoading;
      _room = matrix.client.getRoomById(roomId);
      if (_room == null) return;
    }

    try {
      timeline = await _room!.getTimeline(onUpdate: updateView);
      timeline!.requestKeys(onlineKeyBackupOnly: false);
    } catch (e) {
      if (!mounted) return;
      timeline = await _room!.getTimeline(onUpdate: updateView);
    }
    if (!mounted) return;
    // 关键：timeline 就绪后立刻刷新界面。
    // 原版通过 FutureBuilder(loadTimelineFuture) 实现同样效果；
    // 缺了这一步界面会一直停在加载态，直到下一次 sync 才渲染，
    // 这正是首次打开要等数秒的原因（消息其实早已在内存中）。
    if (_room!.markedUnread) _room!.markUnread(false);
    setReadMarker();
    setState(() {});
    _shareItems();
    _checkCallSupport();

    // 通话等场景（CallKit 来电使 app 退到后台、房间事件超过 sync 窗口）后
    // 会收到 limited sync，SDK 此时会清空数据库里的房间时间线片段，
    // 重进聊天时只剩最后一小段且往往全是被隐藏的通话状态事件，
    // 界面误显示"尚无消息"。这种情况下自动向服务器补拉一页历史。
    // 时间线里已有 m.room.create 说明房间从头就是空的，无需补拉。
    if (_needsHistoryBackfill(timeline!)) {
      await requestHistory();
    }

    _onSyncUpdate = matrix.client.onSync.stream.listen((sync) {
      if (!mounted) return;
      setState(() {});
      // 聊天页在通话浮层下方仍然存活时，也要在断层后自动补拉
      final tl = timeline;
      if (tl != null &&
          sync.rooms?.join?[roomId]?.timeline?.limited == true &&
          _needsHistoryBackfill(tl)) {
        requestHistory();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setReadMarker();
      // 搜索结果跳转：进入聊天后自动定位到指定事件
      final eventId = widget.eventId;
      if (eventId != null && eventId.isNotEmpty) {
        scrollToEventId(eventId);
      }
    });
  }

  void updateView() {
    if (!mounted) return;
    setReadMarker();
    setState(() {});
  }

  /// 转发 / 分享内容：将通过路由 extra 传入的 [ShareItem] 发送到当前房间
  Future<void> _shareItems() async {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!mounted) return;
    final r = _room;
    if (r == null) return;
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) {
        await r.sendTextEvent(item.value);
      } else if (item is ContentShareItem) {
        await r.sendEvent(item.value.copy());
      }
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isNotEmpty && mounted) {
      await _showSendFileDialog(files);
    }
  }

  /// 重新加载时间线（例如清空聊天记录后刷新界面）
  Future<void> reloadTimeline() async {
    _onSyncUpdate?.cancel();
    timeline?.cancelSubscriptions();
    timeline = null;
    if (mounted) setState(() {});
    await _loadTimeline();
  }

  /// 时间线中是否存在界面会实际渲染的事件。
  /// 判定口径必须与 ChatV2View 的 visibleEvents 过滤保持一致。
  bool _hasVisibleEvents(Timeline tl) => tl.events.any((event) {
    if (event.relationshipType == RelationshipTypes.thread) return false;
    if (event.type == RtcNotificationContent.eventType) return true;
    if (!event.isVisibleInGui) return false;
    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return false;
    }
    return true;
  });

  /// limited sync 断层后，时间线里没有可显示事件时需要自动补拉历史。
  /// 已有 m.room.create 的真空房间不需要。
  bool _needsHistoryBackfill(Timeline tl) =>
      !_hasVisibleEvents(tl) &&
      tl.canRequestHistory &&
      !tl.events.any((event) => event.type == EventTypes.RoomCreate);

  /// 每次向服务器/本地库请求的历史消息条数
  static const int loadHistoryCount = 100;

  bool _requestingHistory = false;
  Timer? _retentionTimer;

  /// 房间 m.room.retention 的 max_lifetime（毫秒），未设置返回 null
  int? get retentionMaxLifetime {
    final content = room.getState('m.room.retention')?.content;
    final v = content?['max_lifetime'];
    return v is int && v > 0 ? v : null;
  }

  /// 时间线中最老的「消息类」事件时间戳（排除状态事件，否则 m.room.create
  /// 等远古状态事件会让 retention 截止判断立刻命中）。无消息返回 null。
  DateTime? get oldestMessageTs {
    final messages = timeline?.events
        .where((e) => e.stateKey == null)
        .map((e) => e.originServerTs);
    if (messages == null || messages.isEmpty) return null;
    return messages.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// 向更早方向分页加载历史。Timeline 初始只持有有限的事件窗口，
  /// 不调用它的话列表滚到顶就"没有更多"了。
  /// 若房间启用了自动删除（max_lifetime），且时间线最老的事件已早于
  /// 截止时间，则不再请求更早历史，保证拉不到已清除的消息。
  Future<void> requestHistory() async {
    final timeline = this.timeline;
    if (timeline == null ||
        _requestingHistory ||
        !timeline.canRequestHistory ||
        timeline.isRequestingHistory) {
      return;
    }
    // retention 截止：最老消息已过期则停止加载更早历史
    final maxLifetime = retentionMaxLifetime;
    final oldest = oldestMessageTs;
    if (maxLifetime != null &&
        oldest != null &&
        DateTime.now().difference(oldest).inMilliseconds >= maxLifetime) {
      return;
    }
    _requestingHistory = true;
    // 刷新顶部加载指示器
    if (mounted) setState(() {});
    try {
      await timeline.requestHistory(historyCount: loadHistoryCount);
    } catch (e) {
      Logs().w('Unable to request history', e);
    } finally {
      _requestingHistory = false;
      if (mounted) setState(() {});
    }
  }

  /// 查询 homeserver 是否配置了 LiveKit 通话服务（与原版一致）
  Future<void> _checkCallSupport() async {
    try {
      final urls = await room.client.getLiveKitServiceUrls();
      if (urls.isNotEmpty && mounted) {
        setState(() => supportsCalls = true);
        // 点击通话通知进入：确认服务支持后自动发起语音呼叫，
        // 避免通话从原版路由发起导致挂断后落回原版界面。
        if (widget.action == 'call' &&
            Matrix.of(context).activeCallRoomId.value == null) {
          await startCall(MatrixRtcCallIntent.voice);
        }
      }
    } catch (e) {
      Logs().d('Unable to check MatrixRTC call support', e);
    }
  }

  /// 当前房间是否允许我发起/加入 MatrixRTC 通话：
  /// 服务器支持 LiveKit 即可显示通话入口，权限（m.call.member 写入）
  /// 由 startCall 内的 ensureMatrixRtcCallPermission 在发起时兜底处理。
  /// 群聊中普通成员也能主动发起/加入通话：FluffyChat 创建的群已将
  /// 该事件级别开放为 0，其他客户端创建的群若未开放则提示不允许。
  bool get canCallInRoom => supportsCalls;

  /// 发起语音/视频通话（群聊中已有进行中的通话时变为「加入通话」，
  /// 意图跟随已有通话）：通话页由全局 CallOverlay 承载，
  /// 返回时可缩成迷你悬浮窗而不挂断
  Future<void> startCall(MatrixRtcCallIntent intent) async {
    final matrix = Matrix.of(context);

    // 能改 power levels 的成员（房主/管理员）发起/加入时把 m.call.member
    // 事件级别开放为 0，让所有成员都能入会；普通成员在未开放的老房间里
    // 注定被服务端拒绝（M_FORBIDDEN），直接给出明确提示而不进入通话页。
    final allowed = await room.ensureMatrixRtcCallPermission();
    if (!mounted) return;
    if (!allowed) {
      V2Toast.show(L10n.of(context).callNotAllowed);
      return;
    }

    // 群聊加入进行中的通话：跟随当前通话的意图（视频通话中加入默认开摄像头）
    final activeIntent = room.isDirectChat
        ? intent
        : (room.activeMatrixRtcCallIntent ?? intent);
    matrix.outgoingCallIntent = activeIntent.name;
    matrix.callPosition.value = CallPosition.fullScreen;
    matrix.activeCallRoomId.value = roomId;
  }

  void _updateScrollController() {
    if (!mounted || !scrollController.hasClients) return;
    if (timeline?.allowNewEvent == false ||
        scrollController.position.pixels > 0 && !_scrolledUp) {
      if (!_scrolledUp) setState(() => _scrolledUp = true);
    } else if (scrollController.position.pixels <= 0 && _scrolledUp) {
      setState(() => _scrolledUp = false);
      setReadMarker();
    }
  }

  void _loadDraft() {
    final prefs = Matrix.of(context).store;
    final draft = prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
    }
  }

  void _storeDraft() {
    final prefs = Matrix.of(context).store;
    prefs.setString('draft_$roomId', sendController.text);
  }

  void onInputBarChanged(String text) {
    if (_inputTextIsEmpty != text.isEmpty) {
      setState(() => _inputTextIsEmpty = text.isEmpty);
    }
    _storeDraft();
  }

  /// 当前用户是否还没有在这个私聊里发过任何真正的聊天消息
  ///（对方先发的消息不影响，仅看我自己是否发过；
  /// 验证状态、系统事件等不算聊天消息）
  bool _isMyFirstMessage() {
    final events = timeline?.events;
    if (events == null || events.isEmpty) return true;
    final myId = room.client.userID;
    return !events.any((e) {
      if (e.senderId != myId) return false;
      if (e.type == EventTypes.Sticker) return true;
      if (e.type == EventTypes.Message) {
        return e.messageType != EventTypes.KeyVerificationRequest;
      }
      return false;
    });
  }

  /// 私聊对方是否已经通过密钥验证（masterKey.verified == true）
  bool _otherPartyVerified() {
    final otherId = room.directChatMatrixID;
    if (otherId == null) return false;
    return room.client.userDeviceKeys[otherId]?.masterKey?.verified == true;
  }

  Future<void> send() async {
    if (sendController.text.trim().isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) return;

    // 私聊首次发消息前：若对方尚未验证，提示是否进行交互式验证
    if (room.isDirectChat && _isMyFirstMessage() && !_otherPartyVerified()) {
      final l10n = L10n.of(context);
      final result = await V2ConfirmDialog.show(
        context,
        title: l10n.verifyBeforeFirstMessageTitle,
        message: l10n.verifyBeforeFirstMessageBody,
        confirmLabel: l10n.verifyNow,
        cancelLabel: l10n.sendDirectly,
      );
      if (!mounted) return;
      // 选择「立即验证」：跳转验证页，输入内容保留，暂不发送
      if (result == true) {
        context.push('/v2/rooms/chat/${room.id}/details/verify');
        return;
      }
      // 选择「直接发送」继续往下走；关闭弹窗则不发送
      if (result != false) return;
    }

    final prefs = Matrix.of(context).store;
    prefs.remove('draft_$roomId');

    room.sendTextEvent(
      sendController.text,
      inReplyTo: replyEvent,
      editEventId: editEvent?.eventId,
    );

    setState(() {
      sendController.clear();
      _inputTextIsEmpty = true;
      replyEvent = null;
      editEvent = null;
    });
  }

  /// 发送语音消息（链路移植自原版 ChatController.onVoiceMessageSend）
  Future<void> sendVoiceMessage(
    String path,
    int duration,
    List<int> waveform,
    String fileName,
  ) async {
    if (!room.otherPartyCanReceiveMessages) return;

    Uint8List bytes;
    try {
      // iOS 录音文件实际是 CAF 容器，发送前转成 OGG
      if (PlatformInfos.isCupertinoStyle && fileName.endsWith('.ogg')) {
        bytes = await OggCafConverter().convertCafToOggInMemory(input: path);
      } else {
        bytes = await File(path).readAsBytes();
      }

      final mimeType = lookupMimeType(fileName, headerBytes: bytes);
      var finalName = fileName;
      final extension = mimeType == null ? null : extensionFromMime(mimeType);
      if (extension != null) {
        finalName =
            'voice_message_${DateTime.now().millisecondsSinceEpoch}.$extension';
      }

      var file = MatrixAudioFile(
        bytes: bytes,
        name: finalName,
        mimeType: mimeType,
      );

      // E2EE 房间：包装后 file.encrypt() 将加密派发到后台 isolate，
      // 主 isolate 不阻塞，占位事件立即出现。
      if (room.encrypted) {
        file = wrapWithBackgroundEncryption(file) as MatrixAudioFile;
      }

      // 注册上传进度会话，语音气泡按 txid 读取真实上传进度
      final txid = room.client.generateUniqueTransactionId();
      final uploadSession = UploadProgressManager.instance.start(txid);
      try {
        try {
          await runZoned(
            () => room.sendFileEvent(
              file,
              txid: txid,
              inReplyTo: replyEvent,
              extraContent: {
                'info': {...file.info, 'duration': duration},
                'org.matrix.msc3245.voice': {},
                'org.matrix.msc1767.audio': {
                  'duration': duration,
                  'waveform': waveform,
                },
              },
            ),
            zoneValues: {uploadProgressZoneKey: uploadSession},
          );
        } catch (_) {
          // 用户主动取消：静默结束，不弹错误提示，并清理可能被 SDK
          // 超时重试写回的 error 占位事件。
          if (uploadSession.isCancelled) {
            await removeCancelledSendPlaceholder(room, txid);
            return;
          }
          rethrow;
        }
      } finally {
        UploadProgressManager.instance.end(txid);
      }
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
      return;
    }
    if (mounted) setState(() => replyEvent = null);
  }

  void cancelReply() {
    setState(() {
      replyEvent = null;
      editEvent = null;
    });
  }

  void replyTo(Event event) {
    setState(() {
      replyEvent = event;
      editEvent = null;
    });
    inputFocus.requestFocus();
  }

  // ========== 消息长按操作 ==========

  /// 文本类消息才可复制/编辑
  bool isTextMessage(Event event) =>
      !event.redacted &&
      (event.messageType == MessageTypes.Text ||
          event.messageType == MessageTypes.Notice ||
          event.messageType == MessageTypes.Emote);

  /// 通话相关事件（通话邀请、MatrixRTC 成员状态、RTC 通知）
  /// 不参与多选，避免被复制/转发/删除
  bool isCallRelatedEvent(Event event) =>
      event.type == EventTypes.CallInvite ||
      event.type == RtcNotificationContent.eventType ||
      event.type == MatrixRtcCallMember.eventType ||
      event.type.startsWith('m.call.');

  /// 自己已发送的文本消息才可编辑
  bool canEditEvent(Event event) =>
      event.status.isSent &&
      event.senderId == sendingClient.userID &&
      isTextMessage(event);

  /// 置顶权限
  bool get canPinEvents =>
      room.canChangeStateEvent(EventTypes.RoomPinnedEvents);

  bool isPinned(Event event) => room.pinnedEventIds.contains(event.eventId);

  /// 删除/撤回权限：已发送需为本人或有 canRedact 权限；发送失败的消息任何人都可取消
  bool canRedactEvent(Event event) {
    if (event.status.isSending) return false;
    if (!event.status.isSent) return true; // error 状态可取消发送
    return event.canRedact || event.senderId == sendingClient.userID;
  }

  void editEventAction(Event event) {
    final tl = timeline;
    if (tl == null) return;
    setState(() {
      editEvent = event;
      replyEvent = null;
      sendController.text = event
          .getDisplayEvent(tl)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: false,
            hideReply: true,
          );
      _inputTextIsEmpty = sendController.text.isEmpty;
    });
    inputFocus.requestFocus();
  }

  Future<void> copyEventsAction(List<Event> events) async {
    final tl = timeline;
    if (tl == null || events.isEmpty) return;
    final text = events
        .map((e) => e.getDisplayEvent(tl).body)
        .where((body) => body.isNotEmpty)
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(selectedEvents.clear);
    V2Toast.show(L10n.of(context).copiedToClipboard);
  }

  /// 长按菜单「翻译」：把对方文本消息翻译成当前应用语言并弹窗展示
  Future<void> translateEventAction(Event event) async {
    final tl = timeline;
    if (tl == null) return;
    final text = event.getDisplayEvent(tl).body.trim();
    if (text.isEmpty) return;

    final l10n = L10n.of(context);
    // 当前应用语言，如 zh / en
    final targetLang = l10n.localeName.split('_').first;

    V2Toast.loading(l10n.translating);
    final translated = await TranslationUtil.translate(
      text,
      targetLanguageCode: targetLang,
    );
    V2Toast.dismiss();

    if (!mounted) return;
    if (translated == null || translated.isEmpty) {
      V2Toast.show(l10n.translateFailed);
      return;
    }

    // 译文存入本地存储，气泡下方直接展示，历史消息也可查看
    await TranslationStore.instance.set(event.eventId, translated);
  }

  Future<void> pinEventAction(Event event) async {
    final pinnedEventIds = room.pinnedEventIds.toList();
    if (pinnedEventIds.contains(event.eventId)) {
      pinnedEventIds.remove(event.eventId);
    } else {
      pinnedEventIds.add(event.eventId);
    }
    // 置顶/取消置顶属于常规设置操作，不弹加载框，
    // 服务端同步在后台完成，UI 通过 onRoomState 流自动刷新
    unawaited(room.setPinnedEvents(pinnedEventIds));
  }

  Future<void> forwardEventsAction(List<Event> events) async {
    final tl = timeline;
    if (tl == null || events.isEmpty) return;
    final shareItems = events
        .map((e) => ContentShareItem(e.getDisplayEvent(tl).content.copy()))
        .toList();
    final l10n = L10n.of(context);
    await InviteMembersV2.show(
      context,
      roomId: roomId,
      mode: InviteMembersMode.forward,
      title: l10n.share,
      onConfirm: (roomIds) async {
        if (roomIds.isEmpty) return;
        if (!mounted) return;
        // 向所有选中的房间转发内容
        for (final targetRoomId in roomIds) {
          final targetRoom = sendingClient.getRoomById(targetRoomId);
          if (targetRoom == null) continue;
          for (final item in shareItems) {
            try {
              await targetRoom.sendEvent(item.value.copy());
            } catch (_) {
              // 单个房间发送失败不影响其他房间
            }
          }
        }
        if (mounted) V2Toast.show(l10n.forwarded);
      },
    );
    if (!mounted) return;
    setState(selectedEvents.clear);
  }

  Future<void> redactEventsAction(List<Event> events) async {
    if (events.isEmpty) return;
    final l10n = L10n.of(context);
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.redactMessage,
      message: l10n.redactMessageDescription,
      confirmLabel: l10n.remove,
      cancelLabel: l10n.cancel,
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        for (final event in events) {
          if (event.status.isSent) {
            await event.redactEvent();
          } else {
            await event.cancelSend();
          }
        }
      },
    );
    if (result.error != null) return;
    if (!mounted) return;
    setState(selectedEvents.clear);
  }

  // ========== 多选模式 ==========

  void enterSelectMode(Event event) {
    if (isCallRelatedEvent(event)) return;
    setState(() => selectedEvents.add(event));
  }

  void toggleSelectedEvent(Event event) {
    if (isCallRelatedEvent(event)) return;
    setState(() {
      if (!selectedEvents.remove(event)) selectedEvents.add(event);
    });
  }

  bool isEventSelected(Event event) => selectedEvents.contains(event);

  void clearSelectedEvents() => setState(selectedEvents.clear);

  Future<void> sendFileAction({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty || !mounted) return;
    await _showSendFileDialog(files);
  }

  Future<void> openGallery() async {
    inputFocus.unfocus();

    // wechat_assets_picker 仅支持 Android/iOS，其他平台回退到系统选择器
    if (!PlatformInfos.isMobile) {
      final files = await ImagePicker().pickMultipleMedia(
        requestFullMetadata: false,
      );
      if (files.isEmpty || !mounted) return;
      await _showSendFileDialog(files);
      return;
    }

    final entities = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: 9,
        requestType: RequestType.common,
        gridCount: 4,
        themeColor: V2Theme.of(context).accent,
      ),
    );
    if (entities == null || entities.isEmpty || !mounted) return;
    // 将 AssetEntity 转为 XFile，复用发送文件对话框
    final files = <XFile>[];
    for (final entity in entities) {
      final file = await entity.file;
      if (file != null) {
        files.add(
          XFile(
            file.path,
            name: entity.title ?? file.path.split('/').last,
            length: await file.length(),
            mimeType: entity.mimeType,
          ),
        );
      }
    }
    if (files.isEmpty || !mounted) return;
    await _showSendFileDialog(files);
  }

  Future<void> openCamera() async {
    inputFocus.unfocus();
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null || !mounted) return;
    await _showSendFileDialog([file]);
  }

  /// 居中弹窗展示发送文件对话框，跟随键盘上下浮动
  Future<void> _showSendFileDialog(List<XFile> files) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        // 键盘弹出时整体上移，避免输入框被遮挡
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: Center(
          child: Material(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: 360,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 640),
                child: SendFileDialog(
                  files: files,
                  room: room,
                  outerContext: context,
                  threadRootEventId: null,
                  threadLastEventId: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 计算当前时间线中界面实际会渲染的事件列表，
  /// 过滤口径必须与 ChatV2View 保持一致。
  List<Event> get visibleEvents {
    final tl = timeline;
    if (tl == null) return const [];
    final ignoredUsers = room.client.ignoredUsers;
    final maxLifetime = retentionMaxLifetime;
    final cutoff = maxLifetime != null
        ? DateTime.now().subtract(Duration(milliseconds: maxLifetime))
        : null;
    return tl.events.where((event) {
      if (cutoff != null && event.originServerTs.isBefore(cutoff)) {
        return false;
      }
      if (ignoredUsers.contains(event.senderId)) return false;
      if (event.relationshipType == RelationshipTypes.thread) return false;
      if (event.type == RtcNotificationContent.eventType) return true;
      if (!event.isVisibleInGui) return false;
      return true;
    }).toList();
  }

  /// 滚动到指定事件。若事件不在当前时间线窗口内，
  /// 则以该事件为上下文重新加载时间线后再滚动。
  Future<void> scrollToEventId(String eventId) async {
    final tl = timeline;
    if (tl == null) return;

    final events = visibleEvents;
    final index = events.indexWhere((e) => e.eventId == eventId);
    if (index >= 0) {
      await scrollController.scrollToIndex(
        index,
        duration: const Duration(milliseconds: 300),
        preferPosition: AutoScrollPosition.middle,
      );
      _updateScrollController();
      _triggerHighlight(eventId);
      return;
    }

    // 事件不在当前窗口内，以该事件为上下文重载时间线
    try {
      tl.cancelSubscriptions();
      timeline = await room.getTimeline(
        onUpdate: updateView,
        eventContextId: eventId,
      );
      timeline!.requestKeys(onlineKeyBackupOnly: false);
    } catch (e) {
      Logs().w('Unable to load timeline around event $eventId', e);
      if (!mounted) return;
      timeline = await room.getTimeline(onUpdate: updateView);
    }
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = visibleEvents.indexWhere((e) => e.eventId == eventId);
      if (idx >= 0) {
        scrollController.scrollToIndex(
          idx,
          duration: const Duration(milliseconds: 300),
          preferPosition: AutoScrollPosition.middle,
        );
        _triggerHighlight(eventId);
      }
    });
  }

  /// 让指定消息闪烁高亮，1.5 秒后自动消失
  void _triggerHighlight(String eventId) {
    _highlightTimer?.cancel();
    if (!mounted) return;
    setState(() => highlightEventId = eventId);
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => highlightEventId = null);
    });
  }

  Future<void> scrollDown() async {
    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
      });
      try {
        await _loadTimeline();
      } catch (_) {}
    }
    scrollController.jumpTo(0);
  }

  void setReadMarker({String? eventId}) {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final setOnLatestEvent = eventId == null;
    if (_scrolledUp && setOnLatestEvent) return;
    final tl = timeline;
    if (tl == null || tl.events.isEmpty) return;

    final ignoredUsers = room.client.ignoredUsers;
    eventId ??= tl.events.firstWhereOrNull((event) {
      // 跳过被屏蔽用户的消息，避免对其设置已读回执
      if (ignoredUsers.contains(event.senderId)) return false;
      if (event.eventId == room.lastEvent?.eventId) return true;
      if (room.client.pushruleEvaluator.match(event).notify) return true;
      // 加密事件解密后再匹配一次 push 规则（验证协议事件解密后本地仍
      // 不通知，但普通消息需要）
      final original = event.originalSource;
      if (original != null &&
          room.client.pushruleEvaluator
              .match(Event.fromMatrixEvent(original, room))
              .notify) {
        return true;
      }
      return false;
    })?.eventId;

    // 兜底：时间线窗口里没有匹配本地通知规则的事件（典型场景：整段
    // 都是 m.key.verification.* 验证协议事件，被 isKnownHiddenStates
    // 隐藏、本地不通知，但服务器 notificationCount 仍计数），只要房间
    // 确实有未读，就强制标记到最新事件，否则未读永远清不掉。
    if (setOnLatestEvent && (room.hasNewMessages || room.isUnread)) {
      eventId ??= room.lastEvent?.eventId ?? tl.events.firstOrNull?.eventId;
    }

    if (eventId == null) return;
    if (!eventId.isValidMatrixIdStrict()) return;

    tl
        .setReadMarker(
          eventId: eventId,
          public: AppSettings.sendPublicReadReceipts.value,
        )
        .catchError((Object e) {
          // 已读回执失败不影响使用（例如屏蔽后对方消息事件被服务端拒绝访问），
          // 仅记录日志，不向上抛出。
          debugPrint('[ChatV2] setReadMarker failed: $e');
        });
  }

  Future<void> leaveChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (!mounted) return;
    if (success.error != null) return;
    context.go('/v2/rooms');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setReadMarker();
  }

  @override
  void dispose() {
    // 仅当仍是自己设置的房间 ID 时才清空，避免覆盖其他房间页面设置的值
    if (MatrixState.currentViewingRoomId == room.id) {
      MatrixState.currentViewingRoomId = null;
    }
    _retentionTimer?.cancel();
    _highlightTimer?.cancel();
    _onSyncUpdate?.cancel();
    timeline?.cancelSubscriptions();
    scrollController.dispose();
    inputFocus.dispose();
    sendController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (room.otherPartyCanReceiveMessages) room.setTyping(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatV2View(this);
}
