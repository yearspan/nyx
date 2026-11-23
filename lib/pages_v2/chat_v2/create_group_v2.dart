import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_check_button.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart' as sdk;

/// V2 新建群聊页：填写群名/简介/头像 → 下一步选择成员 → 创建并邀请
class CreateGroupV2 extends StatefulWidget {
  const CreateGroupV2({super.key});

  @override
  State<CreateGroupV2> createState() => _CreateGroupV2State();
}

class _CreateGroupV2State extends State<CreateGroupV2> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  sdk.MatrixFile? _avatar;
  bool _creating = false;

  /// 群名非空才允许下一步
  bool get _canNext => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  /// 选择群头像
  Future<void> _pickAvatar() async {
    sdk.MatrixFile? file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = sdk.MatrixFile(
        bytes: await result.readAsBytes(),
        name: result.path,
      );
    } else {
      final result = await selectFiles(context, type: FileType.image);
      final picked = result.firstOrNull;
      if (picked == null) return;
      file = sdk.MatrixFile(
        bytes: await picked.readAsBytes(),
        name: picked.name,
      );
    }
    setState(() => _avatar = file);
  }

  /// 下一步：弹出 InviteMembersV2 选择成员，确认后创建群聊
  Future<void> _nextStep() async {
    if (!_canNext || _creating) return;
    List<String>? selected;
    await InviteMembersV2.show(
      context,
      roomId: '',
      mode: InviteMembersMode.invite,
      title: L10n.of(context).addMembers,
      onConfirm: (userIds) async {
        selected = userIds;
      },
    );
    if (selected == null || selected!.isEmpty || !mounted) return;
    await _createGroup(selected!);
  }

  /// 创建群聊并邀请选中成员
  Future<void> _createGroup(List<String> inviteUserIds) async {
    if (_creating) return;
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    setState(() => _creating = true);
    try {
      // 上传头像
      Uri? avatarUrl;
      if (_avatar != null) {
        avatarUrl = await client.uploadContent(_avatar!.bytes);
      }

      final initialState = <sdk.StateEvent>[
        if (avatarUrl != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
      ];

      // 私有群默认开启加密
      if (client.encryptionEnabled) {
        initialState.add(
          sdk.StateEvent(
            content: {
              'algorithm': sdk.Client.supportedGroupEncryptionAlgorithms.first,
            },
            type: sdk.EventTypes.Encryption,
          ),
        );
      }

      final roomId = await client.createRoom(
        preset: sdk.CreateRoomPreset.privateChat,
        visibility: sdk.Visibility.private,
        name: _nameController.text.trim(),
        topic: _topicController.text.trim().isEmpty
            ? null
            : _topicController.text.trim(),
        invite: inviteUserIds,
        roomVersion: '12',
        // 普通成员可发起 MatrixRTC 通话
        powerLevelContentOverride: const {
          'events': {'org.matrix.msc3401.call.member': 0},
        },
        initialState: initialState,
      );

      // 等待房间同步
      if (client.getRoomById(roomId) == null) {
        await client.waitForRoomInSync(roomId, join: true);
      }
      if (!mounted) return;
      context.go('/v2/rooms/chat/$roomId');
    } catch (e) {
      if (mounted) V2Toast.show(l10n.oopsSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _creating = false);
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
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              title: l10n.createGroup,
              backIcon: Icons.close,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/v2/rooms');
                }
              },
              action: Padding(
                padding: EdgeInsets.only(right: 12),
                child: V2CheckButton(
                  onTap: _canNext ? _nextStep : null,
                  isLoading: _creating,
                  enabled: _canNext,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 24),
                children: [
                  SizedBox(height: 24),
                  // 群头像
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: V2Theme.of(context).divider,
                          shape: BoxShape.circle,
                          image: _avatar != null
                              ? DecorationImage(
                                  image: MemoryImage(_avatar!.bytes),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _avatar == null
                            ? Icon(
                                Icons.photo_camera,
                                color: V2Theme.of(context).textSecondary,
                                size: 32,
                              )
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(height: 32),
                  // 群聊名称
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).cardBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                  SizedBox(height: 16),
                  // 群简介
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).cardBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                  // SizedBox(height: 12),
                  // Text(
                  //   l10n.chatDescription,
                  //   style: TextStyle(
                  //     color: V2Theme.of(context).textSecondary,
                  //     fontSize: 12,
                  //   ),
                  // ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
