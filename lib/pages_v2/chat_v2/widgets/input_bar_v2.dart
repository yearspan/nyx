import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/create_poll_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/widgets/voice_recorder_v2.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class InputBarV2 extends StatefulWidget {
  final ChatV2Controller controller;

  const InputBarV2({super.key, required this.controller});

  @override
  State<InputBarV2> createState() => _InputBarV2State();
}

class _InputBarV2State extends State<InputBarV2> {
  /// + 号按钮与悬浮菜单的锚点联动
  final LayerLink _attachmentLayerLink = LayerLink();
  OverlayEntry? _attachmentOverlay;

  /// 表情选择面板
  bool _showEmojiPicker = false;

  /// 语音录音
  final VoiceRecorderV2 _voiceRecorder = VoiceRecorderV2();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _hideAttachmentMenu();
    _voiceRecorder.dispose();
    super.dispose();
  }

  /// Web/桌面端：Enter 发送消息，Shift+Enter 换行。
  /// 通过 HardwareKeyboard 全局监听，在事件到达输入框前拦截，
  /// 避免 material_ui 的 TextField 不支持 onKeyEvent。
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || event.synthesized) {
      return false;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return false;
    }
    if (!widget.controller.inputFocus.hasFocus) {
      return false;
    }
    // Shift+Enter 留给默认行为（换行）
    if (HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    widget.controller.send();
    return true;
  }

  Future<void> _startRecording() async {
    if (!PlatformInfos.platformCanRecord) return;
    // 录音前收起其他面板和键盘
    _hideAttachmentMenu();
    if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
    widget.controller.inputFocus.unfocus();

    final started = await _voiceRecorder.start();
    if (!started && mounted) {
      V2Toast.show(L10n.of(context).noPermission);
    }
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      // 收起面板并唤起键盘
      setState(() => _showEmojiPicker = false);
      widget.controller.inputFocus.requestFocus();
      return;
    }
    _hideAttachmentMenu();
    widget.controller.inputFocus.unfocus();
    setState(() => _showEmojiPicker = true);
  }

  /// 在光标处插入表情（逻辑与原版 ChatController.typeEmoji 一致）
  void _onEmojiSelected(Category? category, Emoji emoji) {
    final controller = widget.controller.sendController;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.baseOffset == -1 ? 0 : selection.baseOffset;
    final newText = controller.text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // 组合表情长度可能大于 1
        offset: start + emoji.emoji.length,
      ),
    );
    widget.controller.onInputBarChanged(newText);
  }

  void _emojiBackspace() {
    final controller = widget.controller.sendController;
    controller
      ..text = controller.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    widget.controller.onInputBarChanged(controller.text);
  }

  void _toggleAttachmentMenu() {
    if (_attachmentOverlay != null) {
      _hideAttachmentMenu();
    } else {
      _showAttachmentMenu();
    }
  }

  void _hideAttachmentMenu() {
    _attachmentOverlay?.remove();
    _attachmentOverlay = null;
  }

  /// 在 + 号正上方弹出「相机 / 照片和视频库 / 文件 / 搜索」圆角卡片
  void _showAttachmentMenu() {
    if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
    widget.controller.inputFocus.unfocus();
    final l10n = L10n.of(context);
    final controller = widget.controller;

    final overlay = OverlayEntry(
      builder: (overlayContext) {
        void run(VoidCallback action) {
          _hideAttachmentMenu();
          action();
        }

        Widget row(IconData icon, String label, VoidCallback onTap,{String? img, double?  width}) {
          return InkWell(
            onTap: () => run(onTap),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  img!=null?
                      Image.asset(img,width: width??26,color: Theme.of(context).colorScheme.onSurface,)
                      :
                  Icon(icon, size: 24, color: Theme.of(context).colorScheme.onSurface),
                ],
              ),
            ),
          );
        }

        final menu = Material(
          color: V2Theme.of(context).cardBackground,
          elevation: 12,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 248,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.canCallInRoom) ...[
                  row(
                    Icons.call_outlined,
                    img: "assets/images/setting/voice.png",
                    width: 24,
                    l10n.voiceCall,
                    () => controller.startCall(MatrixRtcCallIntent.voice),
                  ),
                  row(
                    Icons.videocam_outlined,
                    img: "assets/images/setting/video.png",
                    width: 24,
                    l10n.videoCall,
                    () => controller.startCall(MatrixRtcCallIntent.video),
                  ),
                ],
                row(
                  Icons.photo_camera_outlined,
                  img: "assets/images/setting/camera.png",
                  l10n.camera,
                  controller.openCamera,
                ),
                row(
                  Icons.photo_library_outlined,
                  img: "assets/images/setting/image.png",
                  l10n.photosAndVideos,
                  controller.openGallery,
                ),
                row(
                  Icons.insert_drive_file_outlined,
                  img: "assets/images/setting/file.png",
                  l10n.file,
                  controller.sendFileAction,
                ),
                // 投票仅群聊可见
                if (!controller.room.isDirectChat)
                  row(
                    Icons.poll_outlined,
                    img: "assets/images/setting/menu_vote.png",
                    l10n.poll,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CreatePollV2(room: controller.room),
                      ),
                    ),
                  ),
                row(
                  Icons.search,
                  img: "assets/images/setting/search.png",
                  l10n.search,
                  () => context.push('/v2/rooms/chat/${controller.roomId}/search'),
                ),
              ],
            ),
          ),
        );

        return Stack(
          children: [
            // 透明遮罩：点击外部关闭
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideAttachmentMenu,
              ),
            ),
            // 锚定在 + 号上方
            CompositedTransformFollower(
              link: _attachmentLayerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: Offset(0, -12),
              child: menu,
            ),
          ],
        );
      },
    );
    _attachmentOverlay = overlay;
    Overlay.of(context, rootOverlay: true).insert(overlay);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 回复预览
        if (widget.controller.replyEvent != null) _buildReplyPreview(),
        // 输入栏
        Container(
          padding: EdgeInsets.only(left: 8, right: 8, top: 6, bottom: 6),
          color: V2Theme.of(context).cardBackground,
          // 表情面板展开时，底部安全区由面板自身处理
          child: SafeArea(
            top: false,
            bottom: !_showEmojiPicker,
            child: ListenableBuilder(
              listenable: _voiceRecorder,
              builder: (context, _) => _voiceRecorder.isRecording
                  ? _buildRecordingRow(context)
                  : _buildNormalInputRow(context),
            ),
          ),
        ),
        // 表情选择面板（输入栏下方，占据键盘位置）
        _buildEmojiPicker(),
      ],
    );
  }

  /// 普通输入行：+ / 表情 / 文本框 / 语音或发送
  Widget _buildNormalInputRow(BuildContext context) {
    final l10n = L10n.of(context);
    return Row(
      children: [
        // 附件按钮（菜单锚点）
        CompositedTransformTarget(
          link: _attachmentLayerLink,
          child: IconButton(
            icon: Icon(Icons.add, color: V2Theme.of(context).accent, size: 24),
            onPressed: _toggleAttachmentMenu,
          ),
        ),
        // 表情按钮
        IconButton(
          icon: Icon(
            _showEmojiPicker
                ? Icons.keyboard_outlined
                : Icons.emoji_emotions_outlined,
            color: V2Theme.of(context).accent,
            size: 24,
          ),
          onPressed: _toggleEmojiPicker,
        ),
        // 文本输入框
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: V2Theme.of(context).scaffoldBackground,
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              controller: widget.controller.sendController,
              focusNode: widget.controller.inputFocus,
              maxLines: null,
              decoration: InputDecoration(
                hintText: widget.controller.room.encrypted
                    ? l10n.encryptedMessage
                    : l10n.unencryptedMessage,
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF8D8D93),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onTap: () {
                if (_showEmojiPicker) {
                  setState(() => _showEmojiPicker = false);
                }
              },
              onChanged: widget.controller.onInputBarChanged,
              onSubmitted: (_) => widget.controller.send(),
            ),
          ),
        ),
        SizedBox(width: 4),
        // 发送 / 语音 按钮
        if (PlatformInfos.platformCanRecord &&
            widget.controller.inputTextIsEmpty)
          IconButton(
            icon: Icon(Icons.mic, color: V2Theme.of(context).accent, size: 24),
            onPressed: _startRecording,
          )
        else
          IconButton(
            icon: Icon(Icons.send, color: V2Theme.of(context).accent, size: 24),
            onPressed: widget.controller.send,
          ),
      ],
    );
  }

  /// 录音进行中的输入行：取消 / 暂停 / 计时+实时波形 / 发送
  Widget _buildRecordingRow(BuildContext context) {
    final recorder = _voiceRecorder;
    final time =
        '${recorder.duration.inMinutes.toString().padLeft(2, '0')}:'
        '${(recorder.duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          InkWell(
            onTap: recorder.cancel,
            child:
              Container(
                width: 32,height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle),
                child:
                  Image.asset("assets/images/chat/menu/del.png",width: 24,)
              )
          ),
          IconButton(
            icon: Icon(
              recorder.isPaused
                  ? Icons.play_circle_fill_outlined
                  : Icons.pause_circle_outline_outlined,
              color: V2Theme.of(context).textSecondary,
            ),
            tooltip: recorder.isPaused
                ? L10n.of(context).resume
                : L10n.of(context).pause,
            onPressed: recorder.isPaused ? recorder.resume : recorder.pause,
          ),
          SizedBox(
            width: 46,
            child: Text(
              time,
              style: TextStyle(
                fontSize: 14,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
          ),
          // 实时音量波形（右对齐，只显示最新一屏）
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const barWidth = 3.0;
                final visibleCount = (constraints.maxWidth / (barWidth + 2))
                    .floor();
                final amplitudes = recorder.amplitudeTimeline.reversed
                    .take(visibleCount)
                    .toList()
                    .reversed;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final amplitude in amplitudes)
                      Container(
                        margin: EdgeInsets.only(left: 2),
                        width: barWidth,
                        height: 36 * (amplitude / 100).clamp(0.08, 1.0),
                        decoration: BoxDecoration(
                          color: V2Theme.of(context).accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SizedBox(width: 8),
          // 停止并发送
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: V2Theme.of(context).accent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 18,
              ),
              tooltip: L10n.of(context).sendAudio,
              onPressed: () =>
                  recorder.stopAndSend(widget.controller.sendVoiceMessage),
            ),
          ),
          SizedBox(width: 4),
        ],
      ),
    );
  }

  /// 输入栏下方的 emoji 选择面板（复用原版 emoji_picker_flutter）
  Widget _buildEmojiPicker() {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      clipBehavior: Clip.hardEdge,
      height: _showEmojiPicker ? 300 : 0,
      decoration: BoxDecoration(),
      child: _showEmojiPicker
          ? SafeArea(
              top: false,
              child: EmojiPicker(
                onEmojiSelected: _onEmojiSelected,
                onBackspacePressed: _emojiBackspace,
                config: Config(
                  locale: Localizations.localeOf(context),
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: theme.colorScheme.onInverseSurface,
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    enabled: false,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backspaceColor: theme.colorScheme.primary,
                    iconColor: theme.colorScheme.primary.withAlpha(128),
                    iconColorSelected: theme.colorScheme.primary,
                    indicatorColor: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surface,
                    initCategory: Category.SMILEYS
                  ),
                  skinToneConfig: SkinToneConfig(
                    dialogBackgroundColor: Color.lerp(
                      theme.colorScheme.surface,
                      theme.colorScheme.primaryContainer,
                      0.75,
                    )!,
                    indicatorColor: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildReplyPreview() {
    final event = widget.controller.replyEvent!;
    final timeline = widget.controller.timeline;
    final senderName = event.senderFromMemoryOrFallback.calcDisplayname();
    // 引用的消息若已被编辑，显示编辑后的最新内容
    final displayEvent = timeline != null
        ? event.getDisplayEvent(timeline)
        : event;
    final body = displayEvent.body.replaceAll('\n', ' ');

    return Container(
      color: V2Theme.of(context).cardBackground,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: V2Theme.of(context).accent),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 13,
                    color: V2Theme.of(context).accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  body.length > 40 ? '${body.substring(0, 40)}...' : body,
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
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: V2Theme.of(context).textSecondary,
            ),
            onPressed: widget.controller.cancelReply,
          ),
        ],
      ),
    );
  }
}
