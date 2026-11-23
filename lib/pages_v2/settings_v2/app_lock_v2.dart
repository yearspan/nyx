import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';

/// V2 密码锁设置页
///
/// 入口：个人设置 → 隐私与安全 → 锁屏密码。
/// 包含四个状态：未开启 / 设置密码 / 确认密码 / 已开启（关闭或修改）。
class AppLockV2 extends StatefulWidget {
  const AppLockV2({super.key});

  @override
  State<AppLockV2> createState() => _AppLockV2State();
}

enum _Step { intro, verifyOldPasscode, setPasscode, confirmPasscode, manage }

class _AppLockV2State extends State<AppLockV2> {
  _Step _step = _Step.intro;
  String _firstPasscode = '';
  String _currentInput = '';

  /// 验证原密码后的目的：true=关闭密码锁，false=修改密码锁
  bool _verifyForDisable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = AppLock.of(context).isActive;
      if (mounted) setState(() => _step = active ? _Step.manage : _Step.intro);
    });
  }

  /// 数字键盘按键处理
  void _onKey(String key) {
    if (key == 'del') {
      if (_currentInput.isNotEmpty) {
        setState(() => _currentInput = _currentInput.substring(0, _currentInput.length - 1));
      }
      return;
    }
    if (_currentInput.length >= 6) return;
    setState(() => _currentInput += key);
    if (_currentInput.length == 6) {
      _onPasscodeComplete();
    }
  }

  /// 6 位密码输入完成
  Future<void> _onPasscodeComplete() async {
    if (_step == _Step.verifyOldPasscode) {
      final correct = AppLock.of(context).verifyPincode(_currentInput);
      if (correct) {
        if (_verifyForDisable) {
          await AppLock.of(context).changePincode(null);
          if (!mounted) return;
          V2Toast.show(L10n.of(context).appLockDisabled);
          setState(() {
            _currentInput = '';
            _firstPasscode = '';
            _verifyForDisable = false;
            _step = _Step.intro;
          });
        } else {
          setState(() {
            _currentInput = '';
            _firstPasscode = '';
            _step = _Step.setPasscode;
          });
        }
      } else {
        V2Toast.show(L10n.of(context).wrongOldPasscode);
        setState(() => _currentInput = '');
      }
      return;
    }
    if (_step == _Step.setPasscode) {
      _firstPasscode = _currentInput;
      setState(() {
        _currentInput = '';
        _step = _Step.confirmPasscode;
      });
      return;
    }
    if (_step == _Step.confirmPasscode) {
      if (_currentInput == _firstPasscode) {
        await AppLock.of(context).changePincode(_currentInput);
        if (!mounted) return;
        V2Toast.show(L10n.of(context).appLockEnabled);
        setState(() {
          _currentInput = '';
          _firstPasscode = '';
          _step = _Step.manage;
        });
      } else {
        V2Toast.show(L10n.of(context).passcodesDoNotMatch);
        setState(() {
          _currentInput = '';
          _step = _Step.setPasscode;
          _firstPasscode = '';
        });
      }
    }
  }

  /// 关闭锁屏密码：先弹窗确认，再验证原密码，验证通过后关闭
  Future<void> _disableLock() async {
    final l10n = L10n.of(context);
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.disableAppLock,
      message: l10n.disableAppLockAreYouSure,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _verifyForDisable = true;
      _firstPasscode = '';
      _currentInput = '';
      _step = _Step.verifyOldPasscode;
    });
  }

  /// 修改锁屏密码：先验证原密码，再设置新密码
  void _changeLock() {
    setState(() {
      _verifyForDisable = false;
      _firstPasscode = '';
      _currentInput = '';
      _step = _Step.verifyOldPasscode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: L10n.of(context).appLockTitle),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.intro:
        return _buildIntro();
      case _Step.verifyOldPasscode:
        return _buildPasscodeInput(L10n.of(context).verifyOldAppLockPasscode);
      case _Step.setPasscode:
        return _buildPasscodeInput(L10n.of(context).enterAppLockPasscode);
      case _Step.confirmPasscode:
        return _buildPasscodeInput(L10n.of(context).confirmAppLockPasscode);
      case _Step.manage:
        return _buildManage();
    }
  }

  /// 未开启状态
  Widget _buildIntro() {
    final l10n = L10n.of(context);
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: 40,vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: V2Theme.of(context).accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock, color: Colors.white, size: 48),
            ),
            SizedBox(height: 20),
            Text(
              l10n.appLockTitle,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Text(
              l10n.appLockDescription,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: V2Theme.of(context).textSecondary),
            ),
            SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _step = _Step.setPasscode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: V2Theme.of(context).cardBackground,
                  foregroundColor: V2Theme.of(context).accent,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(l10n.enableAppLock, style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
    );
  }

  /// 密码输入状态（设置 / 确认共用）
  Widget _buildPasscodeInput(String title) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _currentInput.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.symmetric(horizontal: 10),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? V2Theme.of(context).accent : V2Theme.of(context).divider,
              ),
            );
          }),
        ),
        SizedBox(height: 72),
        _buildKeypad(),
      ],
    );
  }

  /// 数字键盘 —— V2 风格圆形白底按钮
  Widget _buildKeypad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 56),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          if (k.isEmpty) return SizedBox.shrink();
          final isDel = k == 'del';
          return GestureDetector(
            onTap: () => _onKey(k),
            child: Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDel ? V2Theme.of(context).divider : Colors.white,
                shape: BoxShape.circle,
                boxShadow: isDel
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
              ),
              child: isDel
                  ? Icon(Icons.backspace_outlined, size: 26, color: V2Theme.of(context).textSecondary)
                  : Text(
                      k,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 已开启状态
  Widget _buildManage() {
    final l10n = L10n.of(context);
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: V2Theme.of(context).cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  title: Text(l10n.disableAppLock, style: TextStyle(fontSize: 16, color: V2Theme.of(context).accent),),
                  onTap: _disableLock,
                ),
                Container(height: .5, width: double.infinity,color: Colors.black.withOpacity(.1),),
                ListTile(
                  title: Text(l10n.changeAppLock,style: TextStyle(fontSize: 16, color: V2Theme.of(context).accent),),
                  onTap: _changeLock,
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.appLockForgetWarning,
              style: TextStyle(fontSize: 12, color: V2Theme.of(context).textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
