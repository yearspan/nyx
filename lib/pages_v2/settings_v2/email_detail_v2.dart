import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 邮箱详情页（已绑定邮箱的用户查看）。
///
/// 只读展示当前登录邮箱，底部「修改邮箱」进入修改流程。
class EmailDetailV2 extends StatefulWidget {
  const EmailDetailV2({super.key});

  @override
  State<EmailDetailV2> createState() => _EmailDetailV2State();
}

class _EmailDetailV2State extends State<EmailDetailV2> {
  late Future<List<ThirdPartyIdentifier>?> _emailsFuture = _loadEmails();

  Client get client => Matrix.of(context).client;

  Future<List<ThirdPartyIdentifier>?> _loadEmails() async {
    try {
      return await client.getAccount3PIDs();
    } catch (_) {
      return null;
    }
  }

  Future<void> _onChangeEmail(String email) async {
    final updated = await context.push<bool>('/v2/change-email');
    if (updated == true && mounted) {
      setState(() => _emailsFuture = _loadEmails());
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
              title: l10n.email,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/v2/rooms');
                }
              },
            ),
            Expanded(
              child: FutureBuilder<List<ThirdPartyIdentifier>?>(
                future: _emailsFuture,
                builder: (context, snapshot) {
                  final emails = snapshot.data
                      ?.where(
                        (p) => p.medium == ThirdPartyIdentifierMedium.email,
                      )
                      .toList();
                  final email = emails?.isNotEmpty == true
                      ? emails!.first.address
                      : null;

                  if (email == null) {
                    // 未绑定：引导去绑定
                    return _buildUnbound(l10n);
                  }
                  return _buildContent(l10n, email);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(L10n l10n, String email) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V2FormHeader(
            icon: Icons.markunread_outlined,
            title: l10n.email,
            description: l10n.emailForLogin,
          ),
          SizedBox(height: 32),
          V2FieldLabel(l10n.email),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: V2Theme.of(context).cardBackground,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Text(
              email,
              style: TextStyle(fontSize: 16),
            ),
          ),
          SizedBox(height: 32),
          V2PrimaryButton(
            label: l10n.changeEmail,
            busy: false,
            onTap: () => _onChangeEmail(email),
          ),
        ],
      ),
    );
  }

  Widget _buildUnbound(L10n l10n) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V2FormHeader(
            icon: Icons.markunread_outlined,
            title: l10n.bindEmail,
            description: l10n.bindEmailDescription,
          ),
          SizedBox(height: 32),
          V2PrimaryButton(
            label: l10n.bindEmail,
            busy: false,
            onTap: () => context.push('/v2/bind-email'),
          ),
        ],
      ),
    );
  }
}
