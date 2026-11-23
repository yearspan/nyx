import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_advanced_switch/flutter_advanced_switch.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// V2 加密与恢复密钥页
///
/// 入口：个人设置 → 隐私与安全 → 恢复密钥。
/// 流程：主设置页(开关) → 输入密码页 → 保存恢复密钥页。
class EncryptionV2 extends StatefulWidget {
  const EncryptionV2({super.key});

  @override
  State<EncryptionV2> createState() => _EncryptionV2State();
}

enum _View { main, setPassphrase, saveRecoveryKey }

class _EncryptionV2State extends State<EncryptionV2> {
  _View _view = _View.main;

  bool? _cryptoIdentityConnected;
  late final ValueNotifier<bool> _switchController = ValueNotifier<bool>(false);

  String? _recoveryKey;

  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _repeatController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBootstrap();
    _passphraseController.addListener(_validatePassphrase);
    _repeatController.addListener(_validatePassphrase);
  }

  @override
  void dispose() {
    _switchController.dispose();
    _passphraseController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  Future<void> _checkBootstrap() async {
    try {
      if (!_client.encryptionEnabled || !_client.isLogged()) return;
      await _client.accountDataLoading;
      await _client.userDeviceKeysLoading;
      if (_client.prevBatch == null) {
        await _client.onSync.stream.first;
      }
      final state = await _client.getCryptoIdentityState();
      if (!mounted) return;
      setState(() {
        _cryptoIdentityConnected = state.initialized && state.connected;
      });
      _switchController.value = _cryptoIdentityConnected == true;
    } catch (e) {
      Logs().i('loadkey::$e');
    }
  }

  Client get _client => Matrix.of(context).client;

  // ---- 密码校验 ----
  bool get _passphrasesMatch =>
      _passphraseController.text.isNotEmpty &&
      _passphraseController.text == _repeatController.text;
  bool get _passphraseLongEnough => _passphraseController.text.length >= 12;
  bool get _passphraseUpperAndLowerCase =>
      _passphraseController.text.contains(RegExp(r'[A-Z]')) &&
      _passphraseController.text.contains(RegExp(r'[a-z]'));
  bool get _passphraseSpecialCharacters =>
      _passphraseController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  bool get _passphraseNumbers =>
      _passphraseController.text.contains(RegExp(r'\d'));

  bool get _canSubmit =>
      _passphrasesMatch &&
      _passphraseLongEnough &&
      _passphraseUpperAndLowerCase &&
      _passphraseSpecialCharacters &&
      _passphraseNumbers;

  void _validatePassphrase() {
    if (mounted) setState(() {});
  }

  /// 切换密钥存储开关
  /// 开启时：若加密身份已连接则先弹重置确认，再进入密码设置页。
  Future<void> _toggleKeyStorage(bool value) async {
    if (value && _cryptoIdentityConnected == true) {
      final confirmed = await V2ConfirmDialog.show(
        context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        confirmLabel: L10n.of(context).resetRecoveryKey,
        cancelLabel: L10n.of(context).close,
      );
      if (confirmed != true) {
        _switchController.value = false;
        return;
      }
      if (!mounted) return;
    }
    if (value) {
      // 开启 → 进入密码设置页
      _passphraseController.clear();
      _repeatController.clear();
      setState(() => _view = _View.setPassphrase);
    } else {
      // 关闭：仅擦除在线密钥备份，保留交叉签名与安全存储
      try {
        await _client.initCryptoIdentity(
          setupOnlineKeyBackup: false,
          wipeKeyBackup: true,
          setupMasterKey: false,
          setupSelfSigningKey: false,
          setupUserSigningKey: false,
          wipeCrossSigning: false,
          wipeSecureStorage: false,
        );
        if (!mounted) return;
        setState(() => _cryptoIdentityConnected = false);
        _switchController.value = false;
      } catch (e) {
        if (!mounted) return;
        V2Toast.show(e.toLocalizedString(context));
        _switchController.value = true;
      }
    }
  }

  /// 设置或跳过密码 → 初始化加密身份 → 进入保存恢复密钥页
  Future<void> _submitPassphrase(String? passphrase) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final state = await _client.getCryptoIdentityState();
      if (state.connected) {
        Logs().i('Download the key backup...');
        await _client.encryption!.keyManager.loadAllKeys();
      }
      Logs().i('Init crypto identity...');
      final key = await _client.initCryptoIdentity(passphrase: passphrase);
      if (state.connected) {
        Logs().i('Mark all megolm sessions as needing upload...');
        await _client.database.markInboundGroupSessionsAsNeedingUpload();
      }
      if (!mounted) return;
      setState(() {
        _cryptoIdentityConnected = true;
        _recoveryKey = key;
        _view = _View.saveRecoveryKey;
      });
      _switchController.value = true;
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 复制恢复密钥
  Future<void> _copyRecoveryKey() async {
    if (_recoveryKey == null) return;
    await FluffyShare.share(_recoveryKey!, context, copyOnly: true);
    if (!mounted) return;
    V2Toast.show(L10n.of(context).recoveryKeyCopied);
  }

  /// 保存恢复密钥（标记为已保存）
  void _saveRecoveryKey() {
    V2Toast.show(L10n.of(context).recoveryKeySaved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: L10n.of(context).encryption),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_view) {
      case _View.main:
        return _buildMain();
      case _View.setPassphrase:
        return _buildSetPassphrase();
      case _View.saveRecoveryKey:
        return _buildSaveRecoveryKey();
    }
  }

  /// 主设置页
  Widget _buildMain() {
    final l10n = L10n.of(context);
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        // 允许密钥存储
        Container(
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.allowKeyStorage,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  AdvancedSwitch(
                    controller: _switchController,
                    activeColor: V2Theme.of(context).accent,
                    inactiveColor: Color(0xFFE5E5E5),
                    width: 50,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    onChanged: (v) => _toggleKeyStorage(v as bool),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                l10n.allowKeyStorageDescription,
                style: TextStyle(
                  fontSize: 12,
                  color: V2Theme.of(context).textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 密钥图标（圆形 teal 背景）
  Widget _buildKeyIcon() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: V2Theme.of(context).accent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.vpn_key,
        color: Colors.white,
        size: 36,
      ),
    );
  }

  /// 设置密码页
  Widget _buildSetPassphrase() {
    final l10n = L10n.of(context);
    return ListView(
      padding: EdgeInsets.all(24),
      children: [
        SizedBox(height: 8),
        _buildKeyIcon(),
        SizedBox(height: 20),
        Text(
          l10n.setUpCryptoIdentity,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 12),
        Text(
          l10n.newPassphraseDescription,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: V2Theme.of(context).textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: 24),
        TextField(
          obscureText: _obscureText,
          controller: _passphraseController,
          decoration: InputDecoration(
            hintText: l10n.newPassphrase,
            filled: true,
            fillColor: V2Theme.of(context).cardBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: V2Theme.of(context).divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: V2Theme.of(context).divider),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              onPressed: () => setState(() => _obscureText = !_obscureText),
            ),
          ),
        ),
        SizedBox(height: 12),
        TextField(
          obscureText: _obscureText,
          controller: _repeatController,
          decoration: InputDecoration(
            hintText: l10n.repeatPassphrase,
            filled: true,
            fillColor: V2Theme.of(context).cardBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: V2Theme.of(context).divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: V2Theme.of(context).divider),
            ),
          ),
        ),
        SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _canSubmit && !_isLoading
                ? () => _submitPassphrase(_passphraseController.text)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: V2Theme.of(context).accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(l10n.continueText, style: TextStyle(fontSize: 16)),
          ),
        ),
        SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading ? null : () => _submitPassphrase(null),
          child: Text(l10n.skip),
        ),
        SizedBox(height: 16),
        _PassphraseCheck(
          checked: _passphrasesMatch,
          label: l10n.passphrasesMatch,
        ),
        SizedBox(height: 8),
        _PassphraseCheck(
          checked: _passphraseLongEnough,
          label: l10n.passphraseLengthRequirement,
        ),
        SizedBox(height: 8),
        _PassphraseCheck(
          checked: _passphraseUpperAndLowerCase,
          label: l10n.passphraseUpperAndLowerCaseRequirement,
        ),
        SizedBox(height: 8),
        _PassphraseCheck(
          checked: _passphraseSpecialCharacters,
          label: l10n.passphraseSpecialCharactersRequirement,
        ),
        SizedBox(height: 8),
        _PassphraseCheck(
          checked: _passphraseNumbers,
          label: l10n.passphraseNumberRequirement,
        ),
      ],
    );
  }

  /// 保存恢复密钥（生成后）
  Widget _buildSaveRecoveryKey() {
    final l10n = L10n.of(context);
    final key = _recoveryKey ?? '';
    return Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          SizedBox(height: 24),
          _buildKeyIcon(),
          SizedBox(height: 20),
          Text(
            l10n.youAreReadyToStart,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 12),
          Text(
            l10n.storeRecoveryKeyDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: V2Theme.of(context).textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.recoveryKey,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          SizedBox(height: 10),
          InkWell(
            onTap: _copyRecoveryKey,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: V2Theme.of(context).cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: V2Theme.of(context).divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      key,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.copy_outlined,
                    size: 20,
                    color: V2Theme.of(context).textSecondary,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10),
          Text(
            l10n.clickToCopyRecoveryKey,
            style: TextStyle(fontSize: 12, color: V2Theme.of(context).textSecondary),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveRecoveryKey,
              style: ElevatedButton.styleFrom(
                backgroundColor: V2Theme.of(context).accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                l10n.saveRecoveryKey,
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: V2Theme.of(context).cardBackground,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: BorderSide(color: V2Theme.of(context).divider),
                ),
              ),
              child: Text(l10n.done, style: TextStyle(fontSize: 16)),
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 密码要求检查项
class _PassphraseCheck extends StatelessWidget {
  final bool checked;
  final String label;
  const _PassphraseCheck({required this.checked, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          checked ? Icons.check_circle_outlined : Icons.circle_outlined,
          color: checked ? Colors.green : V2Theme.of(context).textSecondary,
          size: 20,
        ),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: checked ? Theme.of(context).colorScheme.onSurface : V2Theme.of(context).textSecondary,
          ),
        ),
      ],
    );
  }
}
