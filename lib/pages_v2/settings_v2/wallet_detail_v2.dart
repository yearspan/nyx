import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/profile_extension_store.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// V2 钱包地址详情页（只读展示当前钱包地址，可复制）。
class WalletDetailV2 extends StatefulWidget {
  const WalletDetailV2({super.key});

  @override
  State<WalletDetailV2> createState() => _WalletDetailV2State();
}

class _WalletDetailV2State extends State<WalletDetailV2> {
  Client get client => Matrix.of(context).client;

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    v2ShowFormHint(context, L10n.of(context).copiedToClipboard);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final wallet =
        ProfileExtensionStore.get(
          client,
          ProfileExtensionStore.keyWalletAddress,
        ) ??
        '';
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.walletAddress,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/v2/rooms');
                }
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    V2FormHeader(
                      icon: Icons.account_balance_wallet_outlined,
                      title: l10n.walletAddress,
                      description: l10n.walletForLogin,
                    ),
                    SizedBox(height: 32),
                    V2FieldLabel(l10n.ethereumMainnetAddress),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: V2Theme.of(context).cardBackground,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Text(
                        wallet.isEmpty ? l10n.none : wallet,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    SizedBox(height: 32),
                    V2PrimaryButton(
                      label: l10n.copy,
                      busy: false,
                      onTap: wallet.isEmpty ? null : () => _copy(wallet),
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
