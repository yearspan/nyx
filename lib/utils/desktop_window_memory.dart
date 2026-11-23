import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端窗口位置与尺寸记忆。
///
/// 仅在 macOS/Windows/Linux 使用：通过 window_manager 读写窗口几何信息，
/// 持久化到 shared_preferences。移动端与 Web 不初始化本服务。
///
/// 设计要点：
/// - 窗口最大化期间不保存几何信息（此时取到的是整屏尺寸），只记录最大化
///   标志；取消最大化后再保存正常窗口 frame，避免下次启动丢失原尺寸。
/// - 恢复前校验尺寸与坐标的合理性，显示器被拔走等场景下若保存的位置
///   明显在屏幕外则放弃恢复位置，保留原生侧的居中默认窗口。
/// - 程序化恢复期间通过 [_restoring] 屏蔽监听回调，避免触发无效写回。
class DesktopWindowMemory with WindowListener {
  DesktopWindowMemory._();

  static final DesktopWindowMemory instance = DesktopWindowMemory._();

  static const _keyX = 'desktop.window.x';
  static const _keyY = 'desktop.window.y';
  static const _keyWidth = 'desktop.window.width';
  static const _keyHeight = 'desktop.window.height';
  static const _keyMaximized = 'desktop.window.maximized';

  /// 允许恢复的最小窗口尺寸，小于该值说明存储数据异常。
  static const _minWidth = 360.0;
  static const _minHeight = 240.0;

  /// 多显示器坐标空间的合理上限（8K 双屏量级），超出视为脏数据。
  static const _maxCoordinate = 7680.0;

  Timer? _saveDebounce;
  bool _restoring = false;
  bool _initialized = false;

  /// 在 main() 中 AppSettings.init() 完成后调用一次。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    // 兜底：原生侧启动时会先隐藏窗口，若 5 秒后仍不可见（恢复流程异常、
    // 通道卡住等），强制显示，避免出现"进程在跑但没有窗口"的问题。
    Timer(const Duration(seconds: 5), () async {
      try {
        if (!await windowManager.isVisible()) {
          await windowManager.show();
        }
      } catch (_) {}
    });

    // waitUntilReadyToShow 配合原生侧的启动隐藏：窗口在恢复完几何信息
    // 前保持不可见，恢复后统一 show，消除"默认窗口闪现再跳到记忆位置"。
    try {
      await windowManager.waitUntilReadyToShow();
      await _restore();
    } catch (e, s) {
      Logs().w('Failed to restore desktop window frame', e, s);
    } finally {
      // 无论是否有历史数据、恢复是否成功，都必须显示窗口。
      try {
        await windowManager.show();
      } catch (e, s) {
        Logs().w('Failed to show desktop window', e, s);
      }
    }
  }

  /// 恢复上次保存的窗口状态；无历史数据或数据非法时不做任何处理，
  /// 保留各平台原生 runner 提供的默认窗口（macOS 为居中 1280x800）。
  Future<void> _restore() async {
    final prefs = AppSettings.store;
    final x = prefs.getDouble(_keyX);
    final y = prefs.getDouble(_keyY);
    final width = prefs.getDouble(_keyWidth);
    final height = prefs.getDouble(_keyHeight);
    if (x == null ||
        y == null ||
        width == null ||
        height == null ||
        !_isValidFrame(x, y, width, height)) {
      return;
    }

    _restoring = true;
    try {
      await windowManager.setSize(Size(width, height));
      await windowManager.setPosition(Offset(x, y));
      if (prefs.getBool(_keyMaximized) == true) {
        await windowManager.maximize();
      }
    } catch (e, s) {
      Logs().w('Failed to restore desktop window frame', e, s);
    } finally {
      _restoring = false;
    }
  }

  bool _isValidFrame(double x, double y, double width, double height) {
    if (width < _minWidth || height < _minHeight) return false;
    if (width > _maxCoordinate || height > _maxCoordinate) return false;
    if (!x.isFinite || !y.isFinite) return false;
    // 至少保留 120px 的窗口边缘在合理坐标空间内，防止标题栏完全跑到
    // 已断开的显示器坐标上，导致用户找不到窗口。
    if (x < -width + 120 || y < -height + 120) return false;
    if (x > _maxCoordinate || y > _maxCoordinate) return false;
    return true;
  }

  /// 拖拽/缩放事件高频触发，防抖后落盘，避免频繁写 SharedPreferences。
  void _scheduleSave() {
    if (_restoring) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      final prefs = AppSettings.store;
      final maximized = await windowManager.isMaximized();
      await prefs.setBool(_keyMaximized, maximized);
      // 最大化状态下几何信息是整屏尺寸，不保存，保留最大化前的 frame。
      if (maximized) return;

      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      if (!_isValidFrame(
        position.dx,
        position.dy,
        size.width,
        size.height,
      )) {
        return;
      }
      await prefs.setDouble(_keyX, position.dx);
      await prefs.setDouble(_keyY, position.dy);
      await prefs.setDouble(_keyWidth, size.width);
      await prefs.setDouble(_keyHeight, size.height);
    } catch (e, s) {
      Logs().w('Failed to save desktop window frame', e, s);
    }
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowMaximize() => _scheduleSave();

  @override
  void onWindowUnmaximize() {
    // 取消最大化后系统恢复的 frame 需要立即记录一次。
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 100), _saveNow);
  }

  void dispose() {
    _saveDebounce?.cancel();
    windowManager.removeListener(this);
  }
}
