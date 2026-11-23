import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_state.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:fluffychat/pages_v2/chat_v2/key_verification_v2_dialog.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/device_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/view_model_builder.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:fluffychat/widgets_v2/v2_login_scaffold.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';

/// V2 加密身份引导页（Bootstrap）。
///
/// 复用现有 [BootstrapViewModel] 逻辑，UI 采用 V2 设计风格：
/// - [V2AppBar] 统一导航栏
/// - [V2FormHeader] 顶部图标 + 标题 + 描述
/// - [V2TextInput] / [V2VisibilityToggle] 统一输入框样式
/// - [V2PrimaryButton] 主题色主按钮
/// - [V2ConfirmDialog] / [V2Toast] 统一反馈
class BootstrapV2 extends StatelessWidget {
  final bool reset;
  const BootstrapV2({required this.reset, super.key});

  @override
  Widget build(BuildContext context) {
    // 进入加密身份引导页时，强制关闭登录流程中可能残留的 loading 弹窗
    WidgetsBinding.instance.addPostFrameCallback((_) => V2Toast.dismiss());
    return ViewModelBuilder<BootstrapViewModel>(
      create: () =>
          BootstrapViewModel(client: Matrix.of(context).client, reset: reset),
      builder: (context, viewModel, _) {
        final state = viewModel.value;
        final cryptoIdentityState = state.cryptoIdentityState;

        // 已连接且非重置流程，直接进入主页
        if (cryptoIdentityState?.connected == true && !reset) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => viewModel.goToRoomsPageAfterSuccess(context),
          );
        }

        final title = _resolveTitle(context, state);
        final showContinue = state.recoveryKey != null;

        return V2LoginScaffold(
          child: Scaffold(
            backgroundColor: V2Theme.of(context).scaffoldBackground,
            body: Column(
              children: [
                V2AppBar(
                  title: title,
                  showBack: !showContinue,
                  backIcon: Icons.close,
                  onBack: showContinue
                      ? null
                      : () => _onClose(context, viewModel),
                  action: showContinue
                      ? _ContinueCapsuleButton(
                          onTap: () => context.go('/v2/rooms'),
                        )
                      : null,
                ),
                Expanded(
                  child: cryptoIdentityState == null
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: V2Theme.of(context).accent,
                          ),
                        )
                      : !cryptoIdentityState.initialized || state.reset
                          ? state.recoveryKey == null
                              ? _NewPassphraseBody(viewModel)
                              : _StoreRecoveryKeyBody(viewModel)
                          : _RestoreBootstrapBody(viewModel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _resolveTitle(BuildContext context, BootstrapViewModelState state) {
    final l10n = L10n.of(context);
    final cryptoIdentityState = state.cryptoIdentityState;
    if (cryptoIdentityState == null) return l10n.loadingPleaseWait;
    if (cryptoIdentityState.initialized && !state.reset) {
      return l10n.restoreCryptoIdentity;
    }
    if (state.reset) {
      return state.recoveryKey != null
          ? l10n.youAreReadyToStart
          : l10n.resetCryptoIdentity;
    }
    return l10n.setUpCryptoIdentity;
  }

  /// 左上角叉按钮：
  /// - 从设置页 push 进入（重置/恢复加密身份）：直接返回上一页，不影响登录态
  /// - 登录流程进入（路由栈无上一页）：放弃加密设置，登出当前刚登录的
  ///   账号并回到登录入口页，不再弹"跳过聊天备份"确认框。
  ///   client.logout() 的 finally 中必定 clear 本地会话，MatrixState 的
  ///   loggedOut 监听会自动移除 client 并跳转，失败时这里再兜底跳转一次。
  Future<void> _onClose(BuildContext context, BootstrapViewModel viewModel) async {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final l10n = L10n.of(context);
    V2Toast.loading(l10n.logout);
    try {
      await viewModel.client.logout();
    } catch (e, s) {
      Logs().w('Failed to logout when skipping bootstrap', e, s);
    } finally {
      V2Toast.dismiss();
    }
    if (context.mounted) context.go('/');
  }
}

/// 右上角胶囊「继续」按钮（仅在已生成恢复密钥时显示）
class _ContinueCapsuleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ContinueCapsuleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: V2Theme.of(context).accent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          L10n.of(context).continueText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 视图一：设置密码短语
// ---------------------------------------------------------------------------
class _NewPassphraseBody extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const _NewPassphraseBody(this.viewModel);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final canCreate =
        state.newPassphraseEqualsRepeatPassphrase &&
        state.newPassphraseNumbers &&
        state.newPassphraseSpecialCharacters &&
        state.newPassphraseUpperAndLowerCase &&
        state.newPassphraseLongEnough;

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        V2FormHeader(
          icon: Icons.enhanced_encryption_outlined,
          title: l10n.setUpCryptoIdentity,
          description: l10n.newPassphraseDescription,
        ),
        SizedBox(height: 32),
        V2FieldLabel(l10n.newPassphrase),
        SizedBox(height: 8),
        V2TextInput(
          controller: viewModel.newPassphraseController,
          hint: l10n.newPassphrase,
          obscure: state.obscureText,
          readOnly: state.isLoading,
          trailing: V2VisibilityToggle(
            visible: !state.obscureText,
            onTap: viewModel.toggleObscureText,
          ),
        ),
        SizedBox(height: 20),
        V2FieldLabel(l10n.repeatPassphrase),
        SizedBox(height: 8),
        V2TextInput(
          controller: viewModel.repeatPassphraseController,
          hint: l10n.repeatPassphrase,
          obscure: state.obscureText,
          readOnly: state.isLoading,
        ),
        SizedBox(height: 32),
        V2PrimaryButton(
          label: l10n.continueText,
          busy: state.isLoading,
          onTap: canCreate && !state.isLoading
              ? () => viewModel.setOrSkipPassphrase(
                  viewModel.newPassphraseController.text,
                  context,
                )
              : null,
        ),
        SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: state.isLoading
                ? null
                : () => viewModel.setOrSkipPassphrase(null, context),
            child: Text(
              l10n.skip,
              style: TextStyle(color: Color(0xFFFF4D4F), fontSize: 14),
            ),
          ),
        ),
        SizedBox(height: 24),
        _PassphraseCheck(
          checked: state.newPassphraseEqualsRepeatPassphrase,
          label: l10n.passphrasesMatch,
        ),
        SizedBox(height: 12),
        _PassphraseCheck(
          checked: state.newPassphraseLongEnough,
          label: l10n.passphraseLengthRequirement,
        ),
        SizedBox(height: 12),
        _PassphraseCheck(
          checked: state.newPassphraseUpperAndLowerCase,
          label: l10n.passphraseUpperAndLowerCaseRequirement,
        ),
        SizedBox(height: 12),
        _PassphraseCheck(
          checked: state.newPassphraseSpecialCharacters,
          label: l10n.passphraseSpecialCharactersRequirement,
        ),
        SizedBox(height: 12),
        _PassphraseCheck(
          checked: state.newPassphraseNumbers,
          label: l10n.passphraseNumberRequirement,
        ),
      ],
    );
  }
}

/// 密码短语要求项：勾选态显示绿色对勾，未满足显示红色空心圆
class _PassphraseCheck extends StatelessWidget {
  final bool checked;
  final String label;
  const _PassphraseCheck({required this.checked, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          checked ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: checked ? Color(0xFF52C41A) : Color(0xFFFF4D4F),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: checked ? Theme.of(context).colorScheme.onSurface : V2Theme.of(context).textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 视图二：保存恢复密钥
// ---------------------------------------------------------------------------
class _StoreRecoveryKeyBody extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const _StoreRecoveryKeyBody(this.viewModel);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        V2FormHeader(
          icon: Icons.vpn_key_outlined,
          title: l10n.youAreReadyToStart,
          description: l10n.storeRecoveryKeyDescription,
        ),
        SizedBox(height: 32),
        V2TextInput(
          controller: TextEditingController(text: state.recoveryKey),
          hint: '',
          readOnly: true,
          trailing: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FluffyShare.share(state.recoveryKey!, context),
            child: Icon(
              Icons.copy_outlined,
              size: 20,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ),
        SizedBox(height: 24),
        _CheckRow(
          value: state.recoveryKeyDownloaded,
          title: l10n.saveAsFile,
          onChanged: (v) => viewModel.toggleRecoveryKeyDownloaded(v, context),
        ),
        if (viewModel.supportsSecureStorage)
          _CheckRow(
            value: state.recoveryKeyStoredInSecureStorage,
            title: _secureStorageLabel(context),
            onChanged: viewModel.toggleRecoveryKeyStoredInSecureStorage,
          ),
      ],
    );
  }

  String _secureStorageLabel(BuildContext context) {
    final l10n = L10n.of(context);
    if (PlatformInfos.isAndroid) return l10n.storeInAndroidKeystore;
    if (PlatformInfos.isIOS || PlatformInfos.isMacOS) {
      return l10n.storeInAppleKeyChain;
    }
    return l10n.storeSecurlyOnThisDevice;
  }
}

/// 自定义勾选行（白色卡片内），点击整行切换
class _CheckRow extends StatelessWidget {
  final bool value;
  final String title;
  final ValueChanged<bool?> onChanged;
  const _CheckRow({
    required this.value,
    required this.title,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Theme.of(context).cardBackground,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: V2Theme.of(context).accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 视图三：恢复加密身份
// ---------------------------------------------------------------------------
class _RestoreBootstrapBody extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const _RestoreBootstrapBody(this.viewModel);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final keyVerification = state.keyVerification;

    if (keyVerification != null) {
      if (keyVerification.state == KeyVerificationState.askSas) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          KeyVerificationV2Dialog(request: keyVerification).show(context);
        });
      }
    }

    final devices =
        state.connectedDevices
            ?.map(
              (d) => (title: d.displayname, lastActive: d.lastActive, icon: d.icon),
            )
            .toList() ??
        [];

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        V2FormHeader(
          icon: Icons.restore_outlined,
          title: l10n.restoreCryptoIdentity,
          description: keyVerification != null
              ? l10n.restoreBootstrapDevicesDescription
              : l10n.restoreBootstrapEmptyDevicesDescription,
        ),
        SizedBox(height: 24),
        if (keyVerification != null) ...[
          _VerificationStatusTile(viewModel: viewModel),
          SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: V2Theme.of(context).cardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.hardEdge,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: Scrollbar(
                controller: viewModel.devicesScrollController,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  controller: viewModel.devicesScrollController,
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: V2Theme.of(context).accent,
                      child: Icon(devices[i].icon, size: 30, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    title: Text(
                      devices[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      L10n.of(context).lastActiveAgo(
                        devices[i].lastActive.localizedTime(context),
                      ),
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(height: 1, color: V2Theme.of(context).divider)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.or,
                  style: TextStyle(color: V2Theme.of(context).textSecondary),
                ),
              ),
              Expanded(child: Divider(height: 1, color: V2Theme.of(context).divider)),
            ],
          ),
          SizedBox(height: 16),
        ],
        V2FieldLabel(l10n.passphraseOrKey),
        SizedBox(height: 8),
        V2TextInput(
          controller: viewModel.enterPassphraseOrRecovController,
          hint: l10n.passphraseOrKey,
          obscure: state.obscureText,
          readOnly: state.isLoading,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 6),
              V2VisibilityToggle(
                visible: !state.obscureText,
                onTap: viewModel.toggleObscureText,
              ),
              SizedBox(width: 12),
              if (state.isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: V2Theme.of(context).accent,
                  ),
                )
              else
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: state.passphraseOrRecoveryKeyEntered
                      ? () => viewModel.unlock(context)
                      : () => viewModel.openRecoveryKeyFile(context),
                  child: Text(
                    state.passphraseOrRecoveryKeyEntered
                        ? l10n.unlock
                        : l10n.openFile,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: V2Theme.of(context).accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (state.unlockWithError != null) ...[
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              state.unlockWithError!.toLocalizedString(context),
              style: TextStyle(fontSize: 12, color: Color(0xFFFF4D4F)),
            ),
          ),
        ],
        SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => _onResetAccount(context, viewModel),
            child: Text(
              l10n.resetAccount,
              style: TextStyle(color: Color(0xFFFF4D4F), fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onResetAccount(
    BuildContext context,
    BootstrapViewModel viewModel,
  ) async {
    final l10n = L10n.of(context);
    final consent = await V2ConfirmDialog.show(
      context,
      title: l10n.warning,
      message: l10n.resetAccountWarning,
      confirmLabel: l10n.resetAccount,
    );
    if (consent != true) return;
    if (context.mounted) viewModel.startResetAccount();
  }
}

/// 密钥验证状态行：等待中显示转圈，失败显示重试按钮
class _VerificationStatusTile extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const _VerificationStatusTile({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final failed = state.keyVerification?.state ==
            KeyVerificationState.error ||
        state.noSecretsreceived;

    final text = state.waitingForSecrets
        ? l10n.waitingForKeys
        : state.noSecretsreceived
        ? l10n.noKeysTransmitted
        : l10n.restoreBootstrapDevicesDescription;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          failed
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: state.isLoading ? null : viewModel.retryKeyVerification,
                  child: Icon(
                    Icons.refresh_outlined,
                    color: V2Theme.of(context).accent,
                  ),
                )
              : SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: V2Theme.of(context).accent,
                  ),
                ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
