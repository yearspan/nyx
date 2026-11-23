import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/mxc_image_disk_cache.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

/// V2 图片/视频预览页：支持双指缩放、左右切换、下滑关闭
///
/// UI 结构（参考设计稿）：
/// - 顶部栏：返回按钮 + 居中标题（发送者昵称 + 日期胶囊）+ 更多按钮
/// - 更多菜单：在聊天中查看 / 保存 / 转发 / 分享 / 删除
/// - 底部栏：分享 + 删除（视频额外显示投屏/设置）
/// - 视频控制层：后退 15s / 播放暂停 / 前进 15s + 进度条
class ImageViewerV2 extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final BuildContext outerContext;

  const ImageViewerV2(
    this.event, {
    required this.outerContext,
    this.timeline,
    super.key,
  });

  @override
  State<ImageViewerV2> createState() => _ImageViewerV2State();
}

class _ImageViewerV2State extends State<ImageViewerV2> {
  late final ExtendedPageController _pageController;
  late final List<Event> _allEvents;
  final FocusNode _focusNode = FocusNode();
  int _currentIndex = 0;

  // 缓存已加载的图片字节，避免左右滑动重复下载
  final Map<String, Uint8List> _bytesMap = {}; // 原图
  final Map<String, Uint8List> _thumbBytesMap = {}; // 缩略图
  bool _saving = false;

  // 视频控制
  final Map<String, VideoPlayerController> _videoControllers = {};
  VideoPlayerController? _videoController;
  final ValueNotifier<Duration> _videoPosition = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _videoPlaying = ValueNotifier(false);
  final ValueNotifier<double> _playbackSpeed = ValueNotifier(1.0);
  Timer? _positionTimer;
  bool _isDraggingSlider = false;

  // 菜单是否展开
  bool _menuOpen = false;

  // 设置按钮的 LayerLink，用于让速度弹窗定位到按钮旁边
  final LayerLink _settingsLink = LayerLink();
  OverlayEntry? _speedOverlay;

  @override
  void initState() {
    super.initState();
    _allEvents =
        widget.timeline?.events
            .where(
              (e) => {
                MessageTypes.Image,
                MessageTypes.Sticker,
                if (PlatformInfos.supportsVideoPlayer) MessageTypes.Video,
              }.contains(e.messageType),
            )
            .toList()
            .reversed
            .toList() ??
        [widget.event];
    var index = _allEvents.indexWhere((e) => e.eventId == widget.event.eventId);
    if (index < 0) index = 0;
    _currentIndex = index;
    _pageController = ExtendedPageController(initialPage: index);
    // 让键盘左右键可直接切换图片（web/桌面端）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController.dispose();
    _videoController?.removeListener(_onVideoStateChange);
    _positionTimer?.cancel();
    _videoPosition.dispose();
    _videoPlaying.dispose();
    _playbackSpeed.dispose();
    _speedOverlay?.remove();
    super.dispose();
  }

  Event get _currentEvent => _allEvents[_currentIndex];
  bool get _isVideo => _currentEvent.messageType == MessageTypes.Video;

  /// 加载缩略图（低清但快），用于在原图下载完成前先显示内容
  Future<void> _loadThumbnail(Event event) async {
    final id = event.eventId;
    if (_thumbBytesMap[id] != null) return;

    // 1) 磁盘缓存命中则直接读取
    final cached = await MxcImageDiskCache.read(
      rawKey: id,
      isThumbnail: true,
    );
    if (cached != null) {
      _thumbBytesMap[id] = cached;
      if (mounted) setState(() {});
      return;
    }

    // 2) 事件自带缩略图则下载缩略图（比原图小很多，加载快）
    if (!event.hasThumbnail) return;
    try {
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: true,
      );
      if (data.bytes.isEmpty) return;
      _thumbBytesMap[id] = data.bytes;
      await MxcImageDiskCache.write(
        rawKey: id,
        bytes: data.bytes,
        isThumbnail: true,
      );
      if (mounted) setState(() {});
    } catch (_) {
      // 缩略图下载失败不影响原图加载
    }
  }

  /// 加载原图（高清），下载完成后替换缩略图
  Future<void> _loadFullImage(Event event) async {
    final id = event.eventId;
    if (_bytesMap[id] != null) return;

    // 1) 磁盘缓存命中则直接读取，跳过 SDK 读库 + 解密
    final cached = await MxcImageDiskCache.read(
      rawKey: id,
      isThumbnail: false,
    );
    if (cached != null) {
      _bytesMap[id] = cached;
      if (mounted) setState(() {});
      return;
    }

    // 2) 优先从 SDK 本地存储读取，否则下载
    try {
      final local = await event.downloadAndDecryptAttachment(
        fromLocalStoreOnly: true,
      );
      _bytesMap[id] = local.bytes;
      await MxcImageDiskCache.write(
        rawKey: id,
        bytes: local.bytes,
        isThumbnail: false,
      );
      if (mounted) setState(() {});
      return;
    } catch (_) {
      // 本地没有，继续走网络下载
    }

    try {
      final file = await event.downloadAndDecryptAttachment();
      _bytesMap[id] = file.bytes;
      await MxcImageDiskCache.write(
        rawKey: id,
        bytes: file.bytes,
        isThumbnail: false,
      );
      if (mounted) setState(() {});
    } catch (_) {
      // 原图下载失败，保持显示缩略图
    }
  }

  /// 从事件 info 中读取 blurhash，缺失时回退到中性默认值
  String _getBlurHash(Event event) {
    try {
      final blurhash = (event.infoMap as Map<String, dynamic>)
          .tryGet<String>('xyz.amorgan.blurhash');
      if (blurhash != null && blurhash.isNotEmpty) return blurhash;
    } catch (_) {}
    return 'L5H2EC=PM+yV0g-mq.wG9c010J}I';
  }

  /// 构建单张图片页：缩略图优先 → 原图渐进替换 → BlurHash 兜底
  Widget _buildImagePage(Event event) {
    final id = event.eventId;
    // 触发加载（已有缓存时立即返回，无副作用）
    _loadThumbnail(event);
    _loadFullImage(event);

    final fullBytes = _bytesMap[id];
    final thumbBytes = _thumbBytesMap[id];
    final displayBytes = fullBytes ?? thumbBytes;

    // 缩略图和原图都还没好：显示 BlurHash 占位（比空白转圈体验好）
    if (displayBytes == null) {
      final screenSize = MediaQuery.sizeOf(context);
      return Center(
        child: BlurHash(
          blurhash: _getBlurHash(event),
          width: screenSize.width,
          height: screenSize.height,
          fit: BoxFit.contain,
        ),
      );
    }

    return ExtendedImageSlidePage(
      slideType: SlideType.onlyImage,
      slideAxis: SlideAxis.vertical,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        // 缩略图 → 原图切换时用 key 触发 AnimatedSwitcher 淡入动画
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: ExtendedImage.memory(
            displayBytes,
            key: ValueKey('${id}_${fullBytes != null ? 'full' : 'thumb'}'),
            mode: ExtendedImageMode.gesture,
            initGestureConfigHandler: (state) => GestureConfig(
              minScale: 1.0,
              maxScale: 10.0,
              animationMinScale: 0.8,
              animationMaxScale: 10.0,
              cacheGesture: false,
              inPageView: true,
            ),
          ),
        ),
      ),
    );
  }

  // ========== 视频控制 ==========

  void _onVideoControllerReady(String eventId, VideoPlayerController controller) {
    _videoControllers[eventId] = controller;
    if (eventId == _currentEvent.eventId) {
      _attachVideoController(controller);
    }
  }

  void _attachVideoController(VideoPlayerController controller) {
    _videoController?.removeListener(_onVideoStateChange);
    _positionTimer?.cancel();
    _videoController = controller;
    _videoPlaying.value = controller.value.isPlaying;
    _videoPosition.value = controller.value.position;
    controller.addListener(_onVideoStateChange);
    // 用低频定时器刷新进度（每 200ms），避免每帧重建导致卡顿
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        final c = _videoController;
        if (c == null || _isDraggingSlider) return;
        _videoPosition.value = c.value.position;
      },
    );
  }

  /// 仅监听播放/暂停状态变化，不处理进度（进度由 Timer 低频刷新）
  void _onVideoStateChange() {
    final c = _videoController;
    if (c == null) return;
    final playing = c.value.isPlaying;
    if (_videoPlaying.value != playing) {
      _videoPlaying.value = playing;
    }
  }

  void _detachVideoController() {
    _videoController?.removeListener(_onVideoStateChange);
    _positionTimer?.cancel();
    _positionTimer = null;
    _videoController = null;
  }

  Future<void> _togglePlay() async {
    final c = _videoController;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  Future<void> _seekRelative(Duration offset) async {
    final c = _videoController;
    if (c == null) return;
    final duration = c.value.duration;
    var target = c.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    await c.seekTo(target);
  }

  /// 设置播放速度
  Future<void> _setPlaybackSpeed(double speed) async {
    final c = _videoController;
    if (c == null) return;
    await c.setPlaybackSpeed(speed);
    _playbackSpeed.value = speed;
  }

  /// 投屏到桌面端：通过系统分享面板把视频文件发送到其他设备/应用
  Future<void> _castToDesktop() async {
    await _currentEvent.shareFile(context);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // ========== 操作 ==========

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      bool success;
      if (_isVideo) {
        // 视频：通过文件保存对话框下载（各平台通用）
        await _currentEvent.saveFile(context);
        success = true;
      } else {
        // 图片：手机端存相册，web/桌面端弹保存对话框
        final bytes = _bytesMap[_currentEvent.eventId];
        if (bytes == null) {
          success = false;
        } else {
          success = await saveImageBytes(
            bytes,
            name: 'IMG_${DateTime.now().millisecondsSinceEpoch}.png',
          );
        }
      }
      if (!mounted) return;
      V2Toast.show(
        success
            ? L10n.of(context).savedToGallery
            : L10n.of(context).oopsSomethingWentWrong,
      );
    } catch (e) {
      if (mounted) V2Toast.show(L10n.of(context).oopsSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    await _currentEvent.shareFile(context);
  }

  Future<void> _forward() async {
    final tl = widget.timeline;
    final event = _currentEvent;
    final l10n = L10n.of(context);
    // 取显示用的事件内容（处理编辑等情况）
    final content = tl != null
        ? event.getDisplayEvent(tl).content
        : event.content;
    final shareItem = ContentShareItem(content.copy());
    await InviteMembersV2.show(
      context,
      roomId: event.room.id,
      mode: InviteMembersMode.forward,
      title: l10n.share,
      onConfirm: (roomIds) async {
        if (roomIds.isEmpty) return;
        final client = event.room.client;
        for (final targetRoomId in roomIds) {
          final targetRoom = client.getRoomById(targetRoomId);
          if (targetRoom == null) continue;
          try {
            await targetRoom.sendEvent(shareItem.value.copy());
          } catch (_) {
            // 单个房间发送失败不影响其他房间
          }
        }
        if (mounted) V2Toast.show(l10n.forwarded);
      },
    );
  }

  Future<void> _delete() async {
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
    try {
      await _currentEvent.redactEvent();
      if (!mounted) return;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) V2Toast.show(L10n.of(context).oopsSomethingWentWrong);
    }
  }

  /// 在聊天中查看：关闭预览页并滚动定位到对应消息
  Future<void> _viewInChat() async {
    final eventId = _currentEvent.eventId;
    final roomId = _currentEvent.roomId;
    // 从打开预览页的上下文找到聊天页控制器（在聊天页内打开时存在）
    final controller =
        widget.outerContext.findAncestorStateOfType<ChatV2Controller>();
    Navigator.of(context).pop();
    if (controller != null) {
      // 已在聊天页，直接滚动定位
      await Future.delayed(const Duration(milliseconds: 300));
      controller.scrollToEventId(eventId);
    } else {
      // 从媒体/文件等子页打开，导航到聊天页并定位到该消息
      GoRouter.of(widget.outerContext)
          .go('/v2/rooms/chat/$roomId?event=$eventId');
    }
  }

  // ========== 构建 ==========

  @override
  Widget build(BuildContext context) {
    final iconBg = Colors.black.withValues(alpha: 0.45);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            children: [
              ExtendedImageGesturePageView.builder(
                controller: _pageController,
                onPageChanged: (i) {
                  _detachVideoController();
                  setState(() => _currentIndex = i);
                  // 若新页面的视频控制器已就绪，立即接管
                  final c = _videoControllers[_allEvents[i].eventId];
                  if (c != null) _attachVideoController(c);
                },
                itemCount: _allEvents.length,
                itemBuilder: (context, index) {
                  final event = _allEvents[index];
                  if (event.messageType == MessageTypes.Video) {
                    return EventVideoPlayer(
                      event,
                      showControls: false,
                      onVideoPlayerControllerReady: (controller) =>
                          _onVideoControllerReady(event.eventId, controller),
                    );
                  }
                  return _buildImagePage(event);
                },
              ),

              // 左右切换箭头（仅 web / 桌面端显示，手机端靠滑动）
              if (!PlatformInfos.isMobile) ...[
                if (_currentIndex > 0)
                  Positioned(
                    left: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavArrowButton(
                        icon: Icons.chevron_left,
                        onTap: () => _pageController.animateToPage(
                          _currentIndex - 1,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                      ),
                    ),
                  ),
                if (_currentIndex < _allEvents.length - 1)
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavArrowButton(
                        icon: Icons.chevron_right,
                        onTap: () => _pageController.animateToPage(
                          _currentIndex + 1,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                      ),
                    ),
                  ),
              ],

              // 顶部栏
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(iconBg),
              ),

              // 中央播放按钮
              if (_isVideo)
                Positioned.fill(
                  child: _buildCenterPlayButton(),
                ),

              // 视频控制层
              if (_isVideo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 96,
                  child: _buildVideoControls(),
                ),

              // 底部操作栏
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(iconBg),
              ),

              // 更多菜单
              if (_menuOpen)
                Positioned.fill(
                  child: _buildMoreMenu(iconBg),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 顶部栏 ----------

  Widget _buildTopBar(Color iconBg) {
    final event = _currentEvent;
    final senderName = event.senderFromMemoryOrFallback.calcDisplayname();
    final time = event.originServerTs.toLocal();
    final dateStr =
        '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year.toString().substring(2)}';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            V2CircleIconButton(
              background: iconBg,
              iconColor: Colors.white,
              borderColor: Color(0xff6C6C6C),
              icon: Icons.chevron_left,
              onTap: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            // 居中标题胶囊
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: iconBg,
                  borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Color(0xff6C6C6C))
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            V2CircleIconButton(
              background: iconBg,
              iconColor: Colors.white,
              borderColor: Color(0xff6C6C6C),
              icon: Icons.more_horiz,
              onTap: () => setState(() => _menuOpen = true),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 更多菜单 ----------

  Widget _buildMoreMenu(Color iconBg) {
    final l10n = L10n.of(context);
    // 菜单项
    final items = <_MenuItem>[
      _MenuItem(
        icon: Icons.chat_bubble_outline,
        img: "assets/images/chat/chat_look.png",
        label: l10n.viewInChat,
        onTap: _viewInChat,
      ),
      _MenuItem(
        icon: Icons.download_outlined,
        img: "assets/images/chat/save.png",
        label: l10n.save,
        onTap: _saveToGallery,
      ),
      _MenuItem(
        icon: Icons.forward_outlined,
        img: "assets/images/chat/forward.png",
        label: l10n.forward,
        onTap: _forward,
      ),
      _MenuItem(
        icon: Icons.share_outlined,
        img: "assets/images/chat/share.png",
        label: l10n.share,
        onTap: _share,
      ),
      _MenuItem(
        icon: Icons.delete_outline,
        img: "assets/images/chat/del.png",
        label: l10n.delete,
        isDestructive: true,
        onTap: _delete,
      ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => setState(() => _menuOpen = false),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 60,
              right: 12,
              child: GestureDetector(
                onTap: () {}, // 阻止点击穿透
                child: Container(
                  width: 180,
                  decoration: BoxDecoration(
                    color: Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in items)
                        InkWell(
                          onTap: () {
                            setState(() => _menuOpen = false);
                            item.onTap();
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                item.img!=null?
                                Image.asset(item.img!,width: 22,)
                                    :
                                Icon(
                                  item.icon,
                                  size: 20,
                                  color: item.isDestructive
                                      ? Color(0xFFFF453A)
                                      : Colors.white,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: item.isDestructive
                                          ? Color(0xFFFF453A)
                                          : Colors.white,
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
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 底部栏 ----------

  Widget _buildBottomBar(Color iconBg) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // V2CircleIconButton(
            //   background: iconBg,
            //   iconColor: Colors.white,
            //   borderColor: Color(0xff6C6C6C),
            //   icon: Icons.reply,
            //   onTap: _share,
            // ),
            if (_isVideo)
              Container(
                  padding: EdgeInsets.symmetric(horizontal: 14,vertical: 6),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Color(0xff6C6C6C))
                  ),
                  child:
              Row(
                children: [
                  // GestureDetector(
                  //   onTap: _castToDesktop,
                  //   child:
                  //     Image.asset("assets/images/chat/send_pc.png",width: 24,)
                  // ),
                  //SizedBox(width: 16),
                  CompositedTransformTarget(
                    link: _settingsLink,
                    child: GestureDetector(
                        onTap: _showSpeedSelectionSheet,
                        child:
                        Image.asset("assets/images/chat/setting.png",width: 24,)
                    ),
                  ),
                ],
              ))
            else
              SizedBox.shrink(),
            // V2CircleIconButton(
            //   background: iconBg,
            //   iconColor: Colors.white,
            //   borderColor: Color(0xff6C6C6C),
            //   icon: Icons.delete_outline,
            //   onTap: _delete,
            // ),
          ],
        ),
      ),
    );
  }

  // ---------- 视频控制层（仅进度条） ----------

  Widget _buildVideoControls() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      // 进度条：仅随位置刷新（200ms 一次）
      child: ValueListenableBuilder<Duration>(
        valueListenable: _videoPosition,
        builder: (context, position, _) {
          final duration =
              _videoController?.value.duration ?? Duration.zero;
          final progress = duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0;
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 14,vertical: 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Color(0xff6C6C6C))
            ),
            child:
            Row(
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbColor: Colors.white,
                    activeTrackColor: Color(0xFFFF6B4A),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                    overlayColor: Colors.white.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChangeStart: (_) => _isDraggingSlider = true,
                    onChangeEnd: (v) {
                      _isDraggingSlider = false;
                      final c = _videoController;
                      if (c != null) {
                        _videoPosition.value = c.value.position;
                      }
                    },
                    onChanged: (v) {
                      final c = _videoController;
                      if (c == null) return;
                      c.seekTo(duration * v);
                    },
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                _formatDuration(duration),
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          )
          );
        },
      ),
    );
  }

  // ---------- 中央播放控制（后退10s / 播放暂停 / 前进10s） ----------

  Widget _buildCenterPlayButton() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _VideoCircleButton(
            onTap: () => _seekRelative(const Duration(seconds: -10)),
            child: Icon(
              Icons.replay_10,
              color: Colors.white,
              size: 32,
            ),
          ),
          SizedBox(width: 32),
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: _videoPlaying,
                builder: (context, playing, _) => Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
          SizedBox(width: 32),
          _VideoCircleButton(
            onTap: () => _seekRelative(const Duration(seconds: 10)),
            child: Icon(
              Icons.forward_10,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 播放速度选择弹窗（定位在设置按钮旁） ----------

  void _showSpeedSelectionSheet() {
    // 已打开则关闭
    if (_speedOverlay != null) {
      _speedOverlay?.remove();
      _speedOverlay = null;
      return;
    }

    const speeds = [0.5, 1.0, 1.5, 2.0];
    final overlay = Overlay.of(context);
    final l10n = L10n.of(context);

    final Widget popup = Material(
      color: Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 180,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  l10n.playbackSpeed,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ValueListenableBuilder<double>(
                valueListenable: _playbackSpeed,
                builder: (context, current, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: speeds.map((speed) {
                    final isSelected = speed == current;
                    final label = speed == 1.0
                        ? l10n.normalSpeed
                        : '${speed.toStringAsFixed(1)}x';
                    return InkWell(
                      onTap: () {
                        _setPlaybackSpeed(speed);
                        _closeSpeedOverlay();
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: isSelected
                                      ? Color(0xFFFF6B4A)
                                      : Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check,
                                color: Color(0xFFFF6B4A),
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _speedOverlay = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // 点击外部关闭
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeSpeedOverlay,
              behavior: HitTestBehavior.opaque,
              child: SizedBox.expand(),
            ),
          ),
          // 跟随设置按钮定位
          CompositedTransformFollower(
            link: _settingsLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: Offset(0, -8),
            child: popup,
          ),
        ],
      ),
    );

    overlay.insert(_speedOverlay!);
  }

  void _closeSpeedOverlay() {
    _speedOverlay?.remove();
    _speedOverlay = null;
  }

  void _onKeyEvent(KeyEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (_currentIndex > 0) {
          _pageController.animateToPage(
            _currentIndex - 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
        break;
      case LogicalKeyboardKey.arrowRight:
        if (_currentIndex < _allEvents.length - 1) {
          _pageController.animateToPage(
            _currentIndex + 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
        break;
    }
  }
}

class _MenuItem {
  final IconData icon;
  final String? img;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    this.img,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _VideoCircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _VideoCircleButton({
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// web / 桌面端图片查看器左右切换箭头按钮
class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
