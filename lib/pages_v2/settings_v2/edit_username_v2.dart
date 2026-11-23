import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_check_button.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 用户名编辑页。
///
/// 顶部为「X 关闭 / 用户名标题 / 青色打勾」，下方输入用户名，
/// 展示设置说明、命名规则与实时聊天链接。
///
/// 注意：修改用户名的后端接口尚未提供，保存处为占位（TODO），
/// UI 与本地校验已完整。
class EditUsernameV2 extends StatefulWidget {
  const EditUsernameV2({super.key});

  @override
  State<EditUsernameV2> createState() => _EditUsernameV2State();
}

class _EditUsernameV2State extends State<EditUsernameV2> {
  late final TextEditingController _usernameController;
  bool _busy = false;

  static final RegExp _validUsername = RegExp(r'^[a-z0-9_]{5,}$');

  Client get client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: client.userID?.localpart ?? '',
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String get _host {
    final host = client.homeserver?.host ?? '';
    // host 不含协议
    return host.isEmpty ? 'nstalk.space' : host;
  }

  Future<void> _save() async {
    final l10n = L10n.of(context);
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      v2ShowFormHint(context, '${l10n.pleaseFillOut} ${l10n.username}');
      return;
    }
    if (!_validUsername.hasMatch(username)) {
      v2ShowFormHint(context, l10n.usernameRuleHint);
      return;
    }
    setState(() => _busy = true);
    // TODO(接口): 调用后端「修改用户名」接口，入参 username。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _busy = false);
    context.pop(true);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/v2/rooms');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(
            title: l10n.username,
            action: Padding(
              padding: EdgeInsets.only(right: 4),
              child: V2CheckButton(
                onTap: _save,
                isLoading: _busy,
              ),
            ),
            onBack: _close,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: AnimatedBuilder(
                animation: _usernameController,
                builder: (context, _) => _buildBody(l10n),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(L10n l10n) {
    final username = _usernameController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V2FieldLabel(l10n.username),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: l10n.username,
                    hintStyle: TextStyle(
                      color: V2Theme.of(context).textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              if (username.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _usernameController.clear();
                    setState(() {});
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(0xFFC9CDD2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 16),
        Text(
          l10n.usernameDescription,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
        SizedBox(height: 16),
        Text(
          l10n.usernameRuleHint,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
        SizedBox(height: 16),
        Text(
          l10n.chatViaLink,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: V2Theme.of(context).textSecondary,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'https://@$username:$_host',
          style: TextStyle(
            fontSize: 14,
            color: V2Theme.of(context).accent,
          ),
        ),
      ],
    );
  }
}

