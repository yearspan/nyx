import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets_v2/v2_single_button_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:terminate_restart/terminate_restart.dart';

/// Shorebird 热更新检查与下载管理。
///
/// 使用方式：
/// - 进入主页时调用 [checkAndShowUpdate] 检查一次
/// - 调用 [startPeriodicCheck] 启动定时轮询（默认 30 分钟）
/// - 页面销毁时调用 [stopPeriodicCheck] 取消定时器
///
/// 流程：checkForUpdate → outdated → update() 下载 → 轮询直到
/// restartRequired → 弹出 V2 对话框 → 点击「立即重启」调用 terminate_restart 重启。
///
/// 所有触发来源（进主页 / 定时器 / 回前台）共用 [_minCheckInterval] 节流，
/// 间隔内的检查请求直接跳过，避免频繁切换应用时反复请求 Shorebird 服务。
class ShorebirdUpdateManager {
  ShorebirdUpdateManager._();

  static final ShorebirdUpdater _updater = ShorebirdUpdater();
  static Timer? _periodicTimer;
  static bool _isChecking = false;
  static bool _dialogShown = false;

  /// 两次实际检查之间的最小间隔。
  /// 无论由哪个入口触发，间隔内的请求都会被跳过
  static const Duration _minCheckInterval = Duration(minutes: 15);

  /// 最近一次实际发起检查的时间，用于节流判断
  static DateTime? _lastCheckAt;

  /// 单次检查：若有新版本则后台下载，就绪后弹出重启对话框。
  ///
  /// 整个过程不阻塞 UI，失败时静默处理（仅打日志），
  /// 避免影响主页正常使用。
  ///
  /// [force] 为 true 时跳过 [_minCheckInterval] 节流（当前无调用方使用，
  /// 预留给将来需要强制检查的场景）。
  static Future<void> checkAndShowUpdate(
    BuildContext context, {
    bool force = false,
  }) async {
    if (_isChecking || _dialogShown) return;
    if (!_updater.isAvailable) return;

    // 节流：checkForUpdate 每次都是真实网络请求，频繁回前台时
    // 间隔内直接跳过，避免无谓的请求与耗电
    final now = DateTime.now();
    if (!force &&
        _lastCheckAt != null &&
        now.difference(_lastCheckAt!) < _minCheckInterval) {
      Logs().v('[Shorebird] check skipped: within min check interval');
      return;
    }
    _lastCheckAt = now;

    _isChecking = true;
    try {
      final status = await _updater.checkForUpdate();

      switch (status) {
        case UpdateStatus.outdated:
          // 有新版本，后台下载补丁
          try {
            await _updater.update();
          } catch (e) {
            // 捕获并发下载或已在下载中的异常，视为触发成功
            if (e.toString().contains('Update already in progress')) {
              Logs().v('[Shorebird] patch already downloading');
            } else {
              rethrow;
            }
          }
          // 轮询等待补丁解压就绪
          final ready = await _waitUntilPatchReady();
          if (ready && context.mounted) {
            _showRestartDialog(context);
          }

        case UpdateStatus.restartRequired:
          // 之前已下载好补丁，直接提示重启
          if (context.mounted) _showRestartDialog(context);

        case UpdateStatus.upToDate:
        case UpdateStatus.unavailable:
          break;
      }
    } catch (e, s) {
      Logs().w('[Shorebird] check or download failed', e, s);
    } finally {
      _isChecking = false;
    }
  }

  /// 启动定时检查，[interval] 默认 30 分钟。
  ///
  /// 返回的 [Timer] 可由调用方自行管理，也可通过 [stopPeriodicCheck] 取消。
  static Timer startPeriodicCheck(
    BuildContext context, {
    Duration interval = const Duration(minutes: 30),
  }) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      if (context.mounted) checkAndShowUpdate(context);
    });
    return _periodicTimer!;
  }

  /// 停止定时检查。
  static void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// 轮询等待补丁下载并解压完毕（状态变为 restartRequired）。
  ///
  /// 每 500ms 检测一次，超时 [timeout]（默认 15s）后放弃本次提示，
  /// 等待下次定时检查再处理。
  static Future<bool> _waitUntilPatchReady({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      try {
        final status = await _updater.checkForUpdate();
        if (status == UpdateStatus.restartRequired) return true;

        final next = await _updater.readNextPatch();
        final current = await _updater.readCurrentPatch();
        if (next != null && next.number != current?.number) return true;
      } catch (_) {
        // 读取失败时继续轮询，不中断
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// 弹出 V2 风格重启对话框，点击「立即重启」后调用 terminate_restart 重启。
  static void _showRestartDialog(BuildContext context) {
    if (_dialogShown) return;
    _dialogShown = true;
    final l10n = L10n.of(context);
    V2SingleButtonDialog.show(
      context,
      title: l10n.updateReadyTitle,
      message: l10n.updateReadyMessage,
      buttonLabel: l10n.restartNow,
      onTap: () async {
        Navigator.of(context).pop(true);
        // 重启应用让 Shorebird 补丁生效。
        // 注意：Shorebird 补丁必须在原生进程重启时才会应用，
        // iOS 上普通的 Flutter Engine 重启（同进程）无效，
        // 必须真正杀掉进程。terminate_restart 在 iOS 上通过
        // URL Scheme 拉起 + exit(0) 实现真正的进程重启。
        await _performRestart();
      },
    ).whenComplete(() => _dialogShown = false);
  }

  /// 执行全平台重启逻辑。
  ///
  /// 按平台选择重启插件：
  /// - iOS / Android / web：使用 terminate_restart。
  ///   iOS 上通过 bundleId:// URL Scheme 拉起 + exit(0) 杀进程，
  ///   **必须杀进程** Shorebird 补丁才会在新进程启动时生效。
  /// - Linux / macOS / Windows：terminate_restart 不支持，
  ///   回退到 restart_app（全平台实现）。
  static Future<void> _performRestart() async {
    if (PlatformInfos.isIOS ||
        PlatformInfos.isAndroid ||
        PlatformInfos.isWeb) {
      await TerminateRestart.instance.restartApp(
        options: const TerminateRestartOptions(terminate: true),
      );
    } else {
      // 桌面端：Linux / macOS / Windows
      await Restart.restartApp();
    }
  }
}
