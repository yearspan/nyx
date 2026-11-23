import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/profile_extension_store.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_check_button.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

/// V2 编辑个人资料页（仿微信风格）。
///
/// - 名字 + 姓氏：合并写入 Matrix displayname，姓氏额外存 account data
/// - 个人简介：复用 presence statusMsg
/// - 邮箱：account 3pid；钱包地址：account data；用户名只读
class EditProfileV2 extends StatefulWidget {
  const EditProfileV2({super.key});

  @override
  State<EditProfileV2> createState() => _EditProfileV2State();
}

class _EditProfileV2State extends State<EditProfileV2> {
  late final TextEditingController _nameController;
  late final TextEditingController _surnameController;
  late final TextEditingController _bioController;

  /// 已选择但尚未上传的新头像
  MatrixFile? _newAvatar;
  bool _saving = false;

  /// 账户 3pid 列表（邮箱），进入页面时只请求一次并缓存
  late final Future<List<ThirdPartyIdentifier>?> _threepidsFuture =
      _loadThreepids();

  Future<List<ThirdPartyIdentifier>?> _loadThreepids() async {
    try {
      return await client.getAccount3PIDs();
    } catch (_) {
      return null;
    }
  }

  Client get client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _surnameController = TextEditingController();
    _bioController = TextEditingController();
    _surnameController.text =
        ProfileExtensionStore.get(
          client,
          ProfileExtensionStore.keySurname,
        ) ??
        '';
    _loadProfile();
    _loadBio();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await client.getProfileFromUserId(client.userID!);
      if (!mounted) return;
      final displayName = profile.displayName ?? '';
      final surname = _surnameController.text;
      // 还原名字：displayname 去掉已保存的姓氏部分
      var name = displayName;
      if (surname.isNotEmpty && name.endsWith(surname)) {
        name = name.substring(0, name.length - surname.length).trim();
      }
      _nameController.text = name;
    } catch (_) {}
  }

  Future<void> _loadBio() async {
    try {
      final presence = await client.fetchCurrentPresence(client.userID!);
      if (mounted) _bioController.text = presence.statusMsg ?? '';
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// 选择新头像
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
  }

  /// 保存全部修改
  Future<void> _save() async {
    if (_saving) return;
    final l10n = L10n.of(context);
    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    if (name.isEmpty) {
      V2Toast.show('${l10n.pleaseFillOut} ${l10n.name}');
      return;
    }

    setState(() => _saving = true);
    try {
      // 1. 头像
      if (_newAvatar != null) {
        await client.setAvatar(_newAvatar);
      }
      // 2. displayname = 名字 + 姓氏
      final newDisplayName = surname.isEmpty ? name : '$name $surname';
      final currentProfile = await client.getProfileFromUserId(
        client.userID!,
      );
      if (newDisplayName != (currentProfile.displayName ?? '')) {
        await client.setProfileField(client.userID!, 'displayname', {
          'displayname': newDisplayName,
        });
      }
      // 3. 姓氏存入扩展字段（用于还原）
      await ProfileExtensionStore.set(
        client,
        ProfileExtensionStore.keySurname,
        surname,
      );
      // 4. 个人简介 → presence statusMsg
      await client.setPresence(
        client.userID!,
        PresenceType.online,
        statusMsg: _bioController.text.trim(),
      );
      // 5. 强制刷新本地 profile 缓存（头像 / 昵称），便于返回设置页立即生效
      await client.getUserProfile(
        client.userID!,
        maxCacheAge: Duration.zero,
      );
      if (mounted) context.pop(true);
    } catch (e) {
      debugPrint('[EditProfile] save failed: $e');
      if (mounted) V2Toast.show(l10n.oopsSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 邮箱行：未绑定 → 绑定邮箱页；已绑定 → 邮箱详情页
  void _onEmailTap(String? email) {
    if (email == null) {
      context.push('/v2/bind-email');
    } else {
      context.push('/v2/email-detail');
    }
  }

  /// 退出登录
  Future<void> _logout() async {
    final l10n = L10n.of(context);
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.areYouSureYouWantToLogout,
      message: l10n.logoutDescription,
      confirmLabel: l10n.logout,
      cancelLabel: l10n.cancel,
      future: () => client.logout(),
    );
    if (confirmed == true && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    // 退出登录过渡帧期间 client 已清空，本页即将随路由替换卸载，渲染空视图即可
    if (!Matrix.of(context).hasLoggedInClient) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(l10n),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  children: [
                    _buildNameCard(l10n),
                    SizedBox(height: 20),
                    _buildBioField(l10n),
                    SizedBox(height: 20),
                    _buildAccountRows(l10n),
                    SizedBox(height: 20),
                    _buildLogout(l10n),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部：取消（左）+ 完成（右），头像悬浮在两者之间
  Widget _buildHeader(L10n l10n) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SizedBox(
        //height: 118,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                V2CircleIconButton(
                  icon: Icons.chevron_left,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/v2/rooms');
                    }
                  },
                ),
                V2CheckButton(onTap: _save, isLoading: _saving),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 14),
                _buildAvatar(),
                SizedBox(height: 8),
                Text(
                  l10n.setNewAvatar,
                  style: TextStyle(
                    fontSize: 14,
                    color: V2Theme.of(context).accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 圆形头像
  Widget _buildAvatar() {
    Widget child;
    if (_newAvatar != null) {
      child = CircleAvatar(
        radius: 44,
        backgroundImage: MemoryImage(_newAvatar!.bytes),
      );
    } else {
      child = FutureBuilder<Profile>(
        future: client.getProfileFromUserId(client.userID!),
        builder: (context, snapshot) => Avatar(
          mxContent: snapshot.data?.avatarUrl,
          name: _nameController.text,
          size: 88,
        ),
      );
    }
    return GestureDetector(onTap: _pickAvatar, child: child);
  }

  /// 名字 / 姓氏 卡片 + 说明
  Widget _buildNameCard(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(V2Theme.cardRadius),
          ),
          child: Column(
            children: [
              _buildInputTile(controller: _nameController, hint: l10n.name),
              Divider(height: 1, indent: 16, color: V2Theme.of(context).divider),
              _buildInputTile(
                controller: _surnameController,
                hint: l10n.surname,
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.nameDescription,
            style: TextStyle(
              fontSize: 13,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputTile({
    required TextEditingController controller,
    required String hint,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        maxLines: 1,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(
            color: V2Theme.of(context).textSecondary,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  /// 个人简介输入框 + 说明
  Widget _buildBioField(L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(V2Theme.cardRadius),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: TextField(
            controller: _bioController,
            maxLines: 1,
            style: TextStyle(fontSize: 16),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: l10n.personalIntro,
              hintStyle: TextStyle(
                color: V2Theme.of(context).textSecondary,
                fontSize: 16,
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.aboutYourselfDescription,
            style: TextStyle(
              fontSize: 13,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// 邮箱 / 钱包地址 / 用户名
  Widget _buildAccountRows(L10n l10n) {
    return FutureBuilder<List<ThirdPartyIdentifier>?>(
      future: _threepidsFuture,
      builder: (context, snapshot) {
        final email = snapshot.data
            ?.where((p) => p.medium == ThirdPartyIdentifierMedium.email)
            .firstOrNull
            ?.address;
        final wallet = ProfileExtensionStore.get(
          client,
          ProfileExtensionStore.keyWalletAddress,
        );

        return Container(
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(V2Theme.cardRadius),
          ),
          child: Column(
            children: [
              _AccountRow(
                icon: Icons.mail_outline,
                iconBg: Color(0xFF22C55E),
                label: l10n.email,
                value: email ?? l10n.bind,
                //onTap: () => _onEmailTap(email),
                showRightIcon:false,
              ),
              Divider(height: 1, indent: 16, color: V2Theme.of(context).divider),
              _AccountRow(
                icon: Icons.account_balance_wallet_outlined,
                iconBg: Color(0xFF3B82F6),
                label: l10n.walletAddress,
                value: wallet ?? l10n.none,
                onTap: () => context.push('/v2/wallet-detail'),
              ),
              Divider(height: 1, indent: 16, color: V2Theme.of(context).divider),
              _AccountRow(
                icon: Icons.alternate_email,
                iconBg: Color(0xFF8B5CF6),
                label: l10n.username,
                value: '@${client.userID?.localpart ?? ''}',
                showRightIcon:false,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 退出登录
  Widget _buildLogout(L10n l10n) {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: V2Theme.of(context).cardBackground,
          borderRadius: BorderRadius.circular(V2Theme.cardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.logout,
                size: 19,
                color: Color(0xFFEF4444),
              ),
            ),
            SizedBox(width: 12),
            Text(
              l10n.logout,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 账户信息行（邮箱 / 钱包 / 用户名）
class _AccountRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool showRightIcon;

  const _AccountRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
    this.onTap,
    this.showRightIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
            if(showRightIcon)
            Icon(
              Icons.chevron_right,
              size: 20,
              color: V2Theme.of(context).textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
