import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_list_v2/chat_list_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/call/incoming_call_watcher.dart';
import 'package:fluffychat/pages_v2/contacts_v2/contacts_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/settings_v2.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/shorebird_update_manager.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:fluffychat/widgets_v2/share_scaffold_dialog_v2.dart';
import 'package:fluffychat/widgets_v2/v2_bottom_nav.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shortcuts_new/flutter_shortcuts_new.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// V2 登录后主页面（3 Tab 容器，全平台适配）
class HomeV2 extends StatefulWidget {
  const HomeV2({super.key});

  @override
  HomeV2State createState() => HomeV2State();
}

class HomeV2State extends State<HomeV2> with WidgetsBindingObserver {
  int _currentIndex = 0;

  // ---- 从旧 ChatList 迁移的初始化订阅 ----
  StreamSubscription? _intentFileStreamSubscription;

  /// App 运行期间监听 MatrixRTC 来电 ring 事件（不依赖系统推送）
  late final IncomingCallWatcher _incomingCallWatcher;

  /// 应用是否曾进入过后台，用于在回到前台时触发一次热更新检查
  bool _wasInBackground = false;

  late final List<Widget> _pages = [
    const ChatListV2(),
    const ContactsV2(),
    const SettingsV2(),
  ];

  List<V2NavItem> _navItems(L10n l10n) => [
    V2NavItem(icon: 'chat', label: l10n.chats),
    V2NavItem(icon: 'contact', label: l10n.contacts),
    V2NavItem(icon: 'setting', label: l10n.settings),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initReceiveSharingIntent();

    _incomingCallWatcher = IncomingCallWatcher(Matrix.of(context))..start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Matrix.of(context).backgroundPush?.setupPush(context);
      //UpdateNotifier.showUpdateDialog(context);
      //UpdateNotifier.showUpdateAvailableBanner(context);

      // Shorebird 热更新：进主页立即检查一次
      ShorebirdUpdateManager.checkAndShowUpdate(context);
      // 之后每 30 分钟轮询一次
      ShorebirdUpdateManager.startPeriodicCheck(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentFileStreamSubscription?.cancel();
    _incomingCallWatcher.dispose();
    ShorebirdUpdateManager.stopPeriodicCheck();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 仅在真正进入后台时标记。
        // inactive 对应下拉通知栏、应用切换器、来电弹窗等瞬时前台中断，
        // 应用并未真正离开，回到 resumed 时不应触发热更新检查
        _wasInBackground = true;
      case AppLifecycleState.resumed:
        // 从后台回到前台时立即触发一次热更新检查
        // （覆盖应用未被杀、但定时器未触发到的时间窗口；
        // Manager 内部有 15 分钟节流，频繁切换不会反复发请求）
        if (_wasInBackground && mounted) {
          _wasInBackground = false;
          ShorebirdUpdateManager.checkAndShowUpdate(context);
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // ---- Share Intent ----

  void _initReceiveSharingIntent() {
    if (!PlatformInfos.isMobile) return;

    // For sharing images coming from outside the app while the app is in memory
    _intentFileStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_processIncomingSharedMedia, onError: print);

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then(
      _processIncomingSharedMedia,
    );

    if (PlatformInfos.isAndroid) {
      final shortcuts = FlutterShortcuts();
      shortcuts.initialize().then(
        (_) => shortcuts.listenAction((action) {
          if (!mounted) return;
          UrlLauncher(context, action).launchUrl();
        }),
      );
    }
  }

  void _processIncomingSharedMedia(List<SharedMediaFile> files) {
    files.removeWhere(
      (file) => file.path.startsWith(AppConfig.deepLinkPrefix) == true,
    );
    if (files.isEmpty) return;

    showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialogV2(
        items: files.map((file) {
          if ({SharedMediaType.text, SharedMediaType.url}.contains(file.type)) {
            return TextShareItem(file.path);
          }
          return FileShareItem(
            XFile(
              file.path.replaceFirst('file://', ''),
              mimeType: file.mimeType,
            ),
          );
        }).toList(),
      ),
    );
  }

  void _onTabTapped(int index) {
    final isWide = FluffyThemes.isColumnMode(context);
    if (isWide) {
      // 宽屏：切左侧面板 Tab，同时把右侧面板重置为空（设置列表在左侧面板内）
      setState(() => _currentIndex = index);
      context.go('/v2/rooms');
    } else {
      setState(() => _currentIndex = index);
    }
  }

  /// 导航栏选中项：窄屏直接用 _currentIndex；
  /// 宽屏根据当前路由判断（设置子页高亮「设置」，聊天页高亮「聊天」）
  int get _navSelectedIndex {
    final isWide = FluffyThemes.isColumnMode(context);
    if (!isWide) return _currentIndex;
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/v2/rooms/chat/')) return 0;
    if (!path.startsWith('/v2/rooms')) return 2;
    return _currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    // 退出登录后、路由过渡完成前，IndexedStack 中的三个 Tab 仍会 build，
    // 此时 client 已清空。直接渲染空视图，避免访问已销毁的 client 崩溃
    if (!Matrix.of(context).hasLoggedInClient) {
      return const SizedBox.shrink();
    }
    final isWide = FluffyThemes.isColumnMode(context);
    final navItems = _navItems(L10n.of(context));

    // 状态栏透明：正常时由各页 ColoredBox 白色顶栏透上来，
    // 弹窗时 scrim 自然覆盖状态栏区域，颜色统一
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: V2Theme.of(context).scaffoldBackground,
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            Expanded(
              child: SafeArea(
                top: false,
                bottom: isWide,
                left: isWide,
                right: true,
                child: Stack(
                  children: [
                    IndexedStack(index: _currentIndex, children: _pages),
                    if (!isWide)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: V2BottomNav(
                          currentIndex: _navSelectedIndex,
                          onTap: _onTabTapped,
                          items: navItems,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isWide)
              V2BottomNav(
                currentIndex: _navSelectedIndex,
                onTap: _onTabTapped,
                items: navItems,
              ),
          ],
        ),
      ),
    );
  }
}
