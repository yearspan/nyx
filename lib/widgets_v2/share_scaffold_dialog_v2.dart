import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_bytes_reader_stub.dart'
    if (dart.library.html) 'package:fluffychat/utils/file_bytes_reader_web.dart'
    if (dart.library.io) 'package:fluffychat/utils/file_bytes_reader_native.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/pre_encrypted_matrix_file.dart';
import 'package:fluffychat/utils/resize_video.dart';
import 'package:fluffychat/utils/upload_progress_manager.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_search_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

/// V2 分享目标选择页（从其他 App 分享内容进来时弹出）
///
/// 支持多选目标房间，点击「转发」后将文本 / 链接 / 图片 / 文件等内容
/// 直接发送到所有选中的房间，无需再次跳转聊天页。
class ShareScaffoldDialogV2 extends StatefulWidget {
  final List<ShareItem> items;

  const ShareScaffoldDialogV2({required this.items, super.key});

  @override
  State<ShareScaffoldDialogV2> createState() => _ShareScaffoldDialogV2State();
}

class _ShareScaffoldDialogV2State extends State<ShareScaffoldDialogV2> {
  final TextEditingController _filterController = TextEditingController();

  final Set<String> _selectedRoomIds = {};
  bool _sending = false;

  void _toggleRoom(String roomId) {
    setState(() {
      if (_selectedRoomIds.contains(roomId)) {
        _selectedRoomIds.remove(roomId);
      } else {
        _selectedRoomIds.add(roomId);
      }
    });
  }

  /// 将所有分享内容发送到选中的每个房间
  Future<void> _forwardAction() async {
    if (_selectedRoomIds.isEmpty || _sending) return;
    final client = Matrix.of(context).client;
    final l10n = L10n.of(context);
    setState(() => _sending = true);
    try {
      for (final roomId in _selectedRoomIds) {
        final room = client.getRoomById(roomId);
        if (room == null) continue;
        for (final item in widget.items) {
          try {
            if (item is TextShareItem) {
              await room.sendTextEvent(item.value);
            } else if (item is ContentShareItem) {
              await room.sendEvent(item.value.copy());
            } else if (item is FileShareItem) {
              await _sendFile(room, item.value);
            }
          } catch (_) {
            // 单个房间 / 单条内容发送失败不阻塞其他
          }
        }
      }
      if (mounted) V2Toast.show(l10n.forwarded);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        while (context.canPop()) {
          context.pop();
        }
      }
    }
  }

  Future<void> _sendFile(Room room, XFile xfile) async {
    final mimeType = xfile.mimeType ?? lookupMimeType(xfile.path);
    final isVideo = mimeType != null && mimeType.startsWith('video');

    // 视频文件发送前先生成封面缩略图，否则事件缺少 thumbnail_url，
    // 接收端气泡只能显示空白占位。
    MatrixImageFile? thumbnail;
    if (isVideo) {
      thumbnail = await xfile.getVideoThumbnail();
    }

    final bytes = await readFileBytes(xfile.path);
    var file = MatrixFile(
      bytes: bytes,
      name: xfile.name,
      mimeType: mimeType,
    ).detectFileType;

    // E2EE 房间：包装后 file.encrypt() 将加密派发到后台 isolate，
    // 主 isolate 不阻塞，占位事件立即出现。图片被 SDK shrink 替换，不包装。
    if (room.encrypted && file is! MatrixImageFile) {
      file = wrapWithBackgroundEncryption(file);
    }

    // 注册上传进度会话，目标房间的消息气泡按 txid 渲染真实上传进度
    final txid = room.client.generateUniqueTransactionId();
    final uploadSession = UploadProgressManager.instance.start(txid);
    try {
      await runZoned(
        () => room.sendFileEvent(
          file,
          txid: txid,
          thumbnail: thumbnail,
          shrinkImageMaxDimension: 1600,
        ),
        zoneValues: {uploadProgressZoneKey: uploadSession},
      );
    } catch (_) {
      if (uploadSession.isCancelled) {
        await removeCancelledSendPlaceholder(room, txid);
      }
      rethrow;
    } finally {
      UploadProgressManager.instance.end(txid);
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final l10n = L10n.of(context);
    final rooms = Matrix.of(context).client.rooms
        .where(
          (room) =>
              room.canSendDefaultMessages &&
              !room.isSpace &&
              room.membership == Membership.join,
        )
        .toList();
    final filter = _filterController.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: v2.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              backgroundColor: v2.scaffoldBackground,
              title: l10n.share,
              backIcon: Icons.close,
              onBack: context.pop,
            ),
            V2SearchBar(
              controller: _filterController,
              hintText: l10n.search,
              onChanged: (_) => setState(() {}),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  final displayname = room.getLocalizedDisplayname(
                    MatrixLocals(l10n),
                  );
                  final selected = _selectedRoomIds.contains(room.id);
                  final filterOut = !displayname.toLowerCase().contains(filter);
                  if (!selected && filterOut) {
                    return const SizedBox.shrink();
                  }
                  return Opacity(
                    opacity: filterOut ? 0.5 : 1,
                    child: FutureBuilder(
                      future: room.loadHeroUsers(),
                      builder: (context, _) => _RoomSelectTile(
                        room: room,
                        name: displayname,
                        selected: selected,
                        onTap: () => _toggleRoom(room.id),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child: _selectedRoomIds.isEmpty
            ? const SizedBox.shrink()
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _forwardAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: v2.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: v2.divider,
                        disabledForegroundColor: Colors.white54,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              l10n.forward,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// 房间选择列表项：左侧圆形复选框 + 房间头像 + 房间名 + 成员数
class _RoomSelectTile extends StatelessWidget {
  final Room room;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _RoomSelectTile({
    required this.room,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final l10n = L10n.of(context);
    final subtitle =
        room.directChatMatrixID ??
        l10n.countParticipants(
          (room.summary.mJoinedMemberCount ?? 0) +
              (room.summary.mInvitedMemberCount ?? 0),
        );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? v2.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? v2.accent : v2.divider,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Avatar(mxContent: room.avatar, name: name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: v2.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
