import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:material_ui/material_ui.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _errorText;
  int _coolDownSeconds = 5;
  bool _inputBlocked = false;
  String _input = '';

  static const int _pinLength = 6;

  Future<void> tryUnlockWithBiometrics() async {
    setState(() => _errorText = null);
    final success = await AppLock.of(context).unlockWithBiometrics();
    if (success) {
      setState(() {
        _inputBlocked = false;
        _errorText = null;
      });
      return;
    }
    _startCooldown();
  }

  void _startCooldown() {
    setState(() {
      _errorText = L10n.of(context).wrongPinEntered(_coolDownSeconds);
      _inputBlocked = true;
      _input = '';
    });
    Future.delayed(Duration(seconds: _coolDownSeconds)).then((_) {
      if (!mounted) return;
      setState(() {
        _inputBlocked = false;
        _coolDownSeconds *= 2;
        _errorText = null;
      });
    });
  }

  Future<void> _tryUnlock() async {
    if (_inputBlocked) return;
    setState(() => _errorText = null);

    final enteredPin = int.tryParse(_input);
    if (enteredPin == null) {
      setState(() => _errorText = L10n.of(context).invalidInput);
      _input = '';
      return;
    }

    if (AppLock.of(context).unlock(_input)) {
      setState(() {
        _inputBlocked = false;
        _errorText = null;
      });
      _input = '';
      return;
    }
    _startCooldown();
  }

  void _onKey(String key) {
    if (_inputBlocked) return;
    if (key == 'del') {
      if (_input.isNotEmpty) {
        setState(() => _input = _input.substring(0, _input.length - 1));
      }
      return;
    }
    if (_input.length >= _pinLength) return;
    setState(() => _input += key);
    if (_input.length == _pinLength) {
      _tryUnlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFA9C9A3), Color(0xFF7FB08A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              // 锁图标
              const Icon(
                Icons.lock,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 20),
              // 标题
              Text(
                l10n.enterLockPasscode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              // 密码点
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (i) {
                  final filled = i < _input.length;
                  return
                    Container(
                    //duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? Colors.white : Colors.transparent,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const Spacer(flex: 1),
              // 数字键盘
              _buildKeypad(),
              const SizedBox(height: 24),
              // 底部操作区：生物识别（左） / 删除（右）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (AppLock.of(context).useBiometrics)
                      GestureDetector(
                        onTap: _inputBlocked ? null : tryUnlockWithBiometrics,
                        child: const Icon(
                          Icons.fingerprint,
                          color: Colors.white,
                          size: 28,
                        ),
                      )
                    else
                      const SizedBox(width: 28),
                    GestureDetector(
                      onTap: _inputBlocked ? null : () => _onKey('del'),
                      child: Text(
                        l10n.delete,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', ''];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          return GestureDetector(
            onTap: _inputBlocked ? null : () => _onKey(k),
            child: Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Text(
                k,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
