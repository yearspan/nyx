import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_check_button.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 群资料编辑页：群主/管理员可修改群头像、群名、群简介
class ChatGroupEditV2 extends StatefulWidget {
  final String roomId;

  const ChatGroupEditV2({super.key, required this.roomId});

  @override
  State<ChatGroupEditV2> createState() => _ChatGroupEditV2State();
}

class _ChatGroupEditV2State extends State<ChatGroupEditV2> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  MatrixFile? _newAvatar;
  bool _saving = false;

  /// 群名非空时才允许保存
  bool get _canSave => _nameController.text.trim().isNotEmpty;

  Room get _room => Matrix.of(context).client.getRoomById(widget.roomId)!;

  @override
  void initState() {
    super.initState();
    final room = _room;
    _nameController.text = room.name;
    _topicController.text = room.topic;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  /// 选择群头像
  Future<void> _pickAvatar() async {
    MatrixFile? file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      final result = await selectFiles(context, type: FileType.image);
      final picked = result.firstOrNull;
      if (picked == null) return;
      file = MatrixFile(bytes: await picked.readAsBytes(), name: picked.name);
    }
    setState(() => _newAvatar = file);
    //V2Toast.show(l10n.changeYourAvatar);
  }

  /// 保存修改
  Future<void> _save() async {
    if (_saving) return;
    final l10n = L10n.of(context);
    final room = _room;
    final newName = _nameController.text.trim();
    final newTopic = _topicController.text.trim();

    if (newName.isEmpty) {
      V2Toast.show(l10n.groupName);
      return;
    }

    setState(() => _saving = true);
    try {
      if (newName != room.name) {
        await room.setName(newName);
      }
      if (newTopic != room.topic.trim()) {
        await room.setDescription(newTopic);
      }
      if (_newAvatar != null) {
        await room.setAvatar(_newAvatar);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[ChatGroupEdit] save failed: $e');
      V2Toast.show(l10n.oopsSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = _room;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              action: V2CheckButton(
                onTap: _save,
                isLoading: _saving,
                enabled: _canSave,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    //SizedBox(height: 24),
                    // 头像
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              if (_newAvatar != null)
                                CircleAvatar(
                                  radius: 44,
                                  backgroundImage: MemoryImage(
                                    _newAvatar!.bytes,
                                  ),
                                )
                              else
                                Avatar(
                                  mxContent: room.avatar,
                                  name: room.name,
                                  size: 88,
                                ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: V2Theme.of(context).accent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: V2Theme.of(
                                        context,
                                      ).scaffoldBackground,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.camera_alt,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            l10n.setNewAvatar,
                            style: TextStyle(
                              fontSize: 14,
                              color: V2Theme.of(context).accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 28),
                    // 群名
                    Container(
                      decoration: BoxDecoration(
                        color: V2Theme.of(context).cardBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _nameController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: l10n.groupName,
                          hintStyle: TextStyle(
                            color: V2Theme.of(context).textSecondary,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    // 简介
                    Container(
                      decoration: BoxDecoration(
                        color: V2Theme.of(context).cardBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _topicController,
                        maxLines: 5,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: l10n.bio,
                          hintStyle: TextStyle(
                            color: V2Theme.of(context).textSecondary,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
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
    );
  }
}
