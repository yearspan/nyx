import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/key_verification_v2_dialog.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/uia_request_manager.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher_string.dart';

import '../config/setting_keys.dart';
import '../utils/account_bundles.dart';
import '../utils/background_push.dart';
import '../widgets_v2/v2_toast.dart';
import 'local_notifications_extension.dart';

class Matrix extends StatefulWidget {
  final Widget? child;

  final List<Client> clients;

  final Map<String, String>? queryParameters;

  final SharedPreferences store;

  const Matrix({
    this.child,
    required this.clients,
    required this.store,
    this.queryParameters,
    super.key,
  });

  @override
  MatrixState createState() => MatrixState();

  /// Returns the (nearest) Client instance of your application.
  static MatrixState of(BuildContext context) =>
      Provider.of<MatrixState>(context, listen: false);
}

class MatrixState extends State<Matrix> {
  int _activeClient = -1;
  String? activeBundle;

  SharedPreferences get store => widget.store;

  BackgroundPush? backgroundPush;

  final ValueNotifier<String?> activeCallRoomId = ValueNotifier(null);
  final ValueNotifier<CallPosition> callPosition = ValueNotifier(
    CallPosition.fullScreen,
  );

  /// 主叫通话的初始意图（'voice' / 'video'），由通话页消费一次后置空
  String? outgoingCallIntent;

  /// 被叫接听时对应的振铃事件 ID，由通话页消费一次后置空，
  /// 用于通话结束后写入通话记录
  String? incomingCallRingEventId;

  Client get client {
    if (_activeClient < 0 || _activeClient >= widget.clients.length) {
      final bundle = currentBundle;
      if (bundle != null && bundle.isNotEmpty) {
        return bundle.first!;
      }
      // 退出登录时 client 会从列表移除，而路由过渡帧中仍有已挂载页面访问
      // client。此处抛出语义明确的异常，调用方应先通过 hasLoggedInClient 判断
      throw StateError(
        'No Matrix client available, all clients have been removed '
        '(logout transition in progress)',
      );
    }
    return widget.clients[_activeClient];
  }

  /// 当前是否存在仍处于登录态的 client。
  /// 退出登录的过渡帧中，已挂载页面应据此提前降级渲染，避免访问已清空的 client 崩溃
  bool get hasLoggedInClient =>
      widget.clients.any((client) => client.isLogged());

  bool get isMultiAccount => widget.clients.length > 1;

  int getClientIndexByMatrixId(String matrixId) =>
      widget.clients.indexWhere((client) => client.userID == matrixId);

  void setActiveClient(Client? cl) {
    final i = widget.clients.indexWhere((c) => c == cl);
    if (i != -1) {
      _activeClient = i;
    } else {
      Logs().w('Tried to set an unknown client ${cl!.userID} as active');
    }
  }

  List<Client?>? get currentBundle {
    if (!hasComplexBundles) {
      return List.from(widget.clients);
    }
    final bundles = accountBundles;
    if (bundles.containsKey(activeBundle)) {
      return bundles[activeBundle];
    }
    return bundles.values.first;
  }

  Map<String?, List<Client?>> get accountBundles {
    final resBundles =
        <String?, List<({Client? client, AccountBundle? bundle})>>{};
    for (var i = 0; i < widget.clients.length; i++) {
      final bundles = widget.clients[i].accountBundles;
      for (final bundle in bundles) {
        if (bundle.name == null) {
          continue;
        }
        resBundles[bundle.name] ??= [];
        resBundles[bundle.name]!.add((
          client: widget.clients[i],
          bundle: bundle,
        ));
      }
    }
    for (final b in resBundles.values) {
      b.sort(
        (a, b) => a.bundle!.priority == null
            ? 1
            : b.bundle!.priority == null
            ? -1
            : a.bundle!.priority!.compareTo(b.bundle!.priority!),
      );
    }
    return resBundles.map(
      (k, v) => MapEntry(k, v.map((vv) => vv.client).toList()),
    );
  }

  bool get hasComplexBundles => accountBundles.values.any((v) => v.length > 1);

  Client? _loginClientCandidate;

  AudioPlayer? audioPlayer;
  final ValueNotifier<String?> voiceMessageEventId = ValueNotifier(null);

  Future<Client> getLoginClient() async {
    if (widget.clients.isNotEmpty && !client.isLogged()) {
      return client;
    }
    final candidate = _loginClientCandidate ??=
        await ClientManager.createClient(
            '${AppSettings.applicationName.value}-${DateTime.now().millisecondsSinceEpoch}',
            store,
          )
          ..onLoginStateChanged.stream
              .where((l) => l == LoginState.loggedIn)
              .first
              .then((_) {
                if (!widget.clients.contains(_loginClientCandidate)) {
                  widget.clients.add(_loginClientCandidate!);
                }
                ClientManager.addClientNameToStore(
                  _loginClientCandidate!.clientName,
                  store,
                );
                _registerSubs(_loginClientCandidate!.clientName);
                setActiveClient(_loginClientCandidate);
                _loginClientCandidate = null;
                FluffyChatApp.router.go('/backup');
              });
    if (widget.clients.isEmpty) widget.clients.add(candidate);
    return candidate;
  }

  Client? getClientByName(String name) =>
      widget.clients.firstWhereOrNull((c) => c.clientName == name);

  /// 当前正在浏览的房间 ID（由 ChatV2 等房间页面在 initState/dispose 时设置/清空）
  /// 用于被踢出群时判断是否需要退回主页
  static String? currentViewingRoomId;

  final onRoomKeyRequestSub = <String, StreamSubscription>{};
  final onKeyVerificationRequestSub = <String, StreamSubscription>{};
  final onNotification = <String, StreamSubscription>{};
  final onLogoutSub = <String, StreamSubscription<LoginState>>{};
  final onUiaRequest = <String, StreamSubscription<UiaRequest>>{};
  final onRoomStateSub = <String, StreamSubscription>{};
  final onSyncSub = <String, StreamSubscription>{};

  String? _cachedPassword;
  Timer? _cachedPasswordClearTimer;

  String? get cachedPassword => _cachedPassword;

  set cachedPassword(String? p) {
    Logs().d('Password cached');
    _cachedPasswordClearTimer?.cancel();
    _cachedPassword = p;
    _cachedPasswordClearTimer = Timer(const Duration(minutes: 10), () {
      _cachedPassword = null;
      Logs().d('Cached Password cleared');
    });
  }

  String? get activeRoomId {
    // 优先使用 ChatV2 主动设置的当前房间 ID（比路由解析更可靠）
    if (currentViewingRoomId != null) return currentViewingRoomId;
    final route = FluffyChatApp.router.routeInformationProvider.value.uri.path;
    // V2 聊天路由：/v2/rooms/chat/:roomId
    if (route.startsWith('/v2/rooms/chat/')) return route.split('/')[4];
    // V2 旧聊天路由（兼容）：/v2/chat/:roomId
    if (route.startsWith('/v2/chat/')) return route.split('/')[3];
    return null;
  }

  /// 退出/被踢出群时的处理：仅当用户正在浏览该房间相关页面时退回主页。
  /// [wasKicked] 为 true 时弹出"您已被踢出此群聊"提示；自己退出则静默退回。
  void _handleKickedFromRoom(String roomId, {required bool wasKicked}) {
    if (activeRoomId != roomId) return;
    if (wasKicked) {
      final ctx =
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        V2Toast.show(L10n.of(ctx).kickedFromGroup);
      }
    }
    FluffyChatApp.router.go('/');
  }

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: didChangeAppLifecycleState);
    initMatrix();
  }

  AppLifecycleListener? _listener;

  void _registerSubs(String name) {
    final c = getClientByName(name);
    if (c == null) {
      Logs().w(
        'Attempted to register subscriptions for non-existing client $name',
      );
      return;
    }
    onRoomKeyRequestSub[name] ??= c.onRoomKeyRequest.stream.listen((
      RoomKeyRequest request,
    ) async {
      if (widget.clients.any(
        ((cl) =>
            cl.userID == request.requestingDevice.userId &&
            cl.identityKey == request.requestingDevice.curve25519Key),
      )) {
        Logs().i(
          '[Key Request] Request is from one of our own clients, forwarding the key...',
        );
        await request.forwardKey();
      }
    });
    onKeyVerificationRequestSub[name] ??= c.onKeyVerificationRequest.stream
        .listen((KeyVerification request) {
          // 手机端进入整页验证；web / 桌面端以弹窗形式展示，视觉更轻量
          if (PlatformInfos.isMobile) {
            FluffyChatApp.router.push('/v2/verify', extra: request);
          } else {
            _showKeyVerificationDialog(request);
          }
        });
    onLogoutSub[name] ??= c.onLoginStateChanged.stream
        .where((state) => state == LoginState.loggedOut)
        .listen((_) {
          final loggedInWithMultipleClients = widget.clients.length > 1;

          _cancelSubs(c.clientName);
          widget.clients.remove(c);
          ClientManager.removeClientNameFromStore(c.clientName, store);
          InitWithRestoreExtension.deleteSessionBackup(name);

          if (loggedInWithMultipleClients) {
            final snackbarContext =
                FluffyChatApp
                    .router
                    .routerDelegate
                    .navigatorKey
                    .currentContext ??
                context;

            if (!snackbarContext.mounted) return;
            final l10n = L10n.of(snackbarContext);
            V2Toast.show(l10n.oneClientLoggedOut);
            return;
          }
          FluffyChatApp.router.go('/');
        });
    onUiaRequest[name] ??= c.onUiaRequest.stream.listen(uiaRequestHandler);

    // 监听房间状态：当当前用户被踢出群（membership 变为 leave），
    // 且当前正在浏览该房间相关页面时，提示并退回主页，避免后续接口报 M_FORBIDDEN
    onRoomStateSub[name] ??= c.onRoomState.stream.listen((update) {
      final event = update.state;
      if (event.type != EventTypes.RoomMember) return;
      if (event.stateKey != c.userID) return;
      if (event.content.tryGet<String>('membership') != Membership.leave.name) {
        return;
      }
      // sender 不是自己 → 被踢出；sender 是自己 → 主动退出
      final wasKicked = event.senderId != c.userID;
      _handleKickedFromRoom(update.roomId, wasKicked: wasKicked);
    });

    // 兜底：监听 onSync，检查当前浏览的房间是否出现在 leave 区块
    // （被踢出后房间会移入 leave，onRoomState 可能因房间已移除而漏触发）
    onSyncSub[name] ??= c.onSync.stream.listen((sync) {
      final currentActiveRoom = activeRoomId;
      if (currentActiveRoom == null) return;
      final leftRooms = sync.rooms?.leave;
      final leftRoom = leftRooms?[currentActiveRoom];
      if (leftRoom == null) return;
      // 从 leave 房间的 state 中查找当前用户的 m.room.member 事件，判断是否被踢
      var wasKicked = true;
      for (final e in leftRoom.state ?? []) {
        if (e.type == EventTypes.RoomMember && e.stateKey == c.userID) {
          wasKicked = e.senderId != c.userID;
          break;
        }
      }
      _handleKickedFromRoom(currentActiveRoom, wasKicked: wasKicked);
    });
    if (PlatformInfos.isWeb || PlatformInfos.isDesktop) {
      FlutterLocalNotificationsPlugin().initialize(
        settings: InitializationSettings(
          linux: LinuxInitializationSettings(
            defaultActionName: FluffyChatNotificationActions.open.name,
          ),
          windows: ClientManager.windowsNotificationSettings,
          macOS: const DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          clients: widget.clients,
          router: FluffyChatApp.router,
          l10n: null,
        ),
      );
      c.onSync.stream.first.then((s) {
        html.Notification.requestPermission();
        onNotification[name] ??= c.onNotification.stream.listen(
          showLocalNotification,
        );
      });
    }
  }

  /// web / 桌面端收到设备验证请求时，以弹窗形式展示（手机端走整页路由）。
  void _showKeyVerificationDialog(KeyVerification request) {
    final context =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    unawaited(
      showDialog<bool>(
        context: context,
        builder: (_) => KeyVerificationV2Dialog(request: request),
      ),
    );
  }

  void _cancelSubs(String name) {
    onRoomKeyRequestSub[name]?.cancel();
    onRoomKeyRequestSub.remove(name);
    onKeyVerificationRequestSub[name]?.cancel();
    onKeyVerificationRequestSub.remove(name);
    onLogoutSub[name]?.cancel();
    onLogoutSub.remove(name);
    onNotification[name]?.cancel();
    onNotification.remove(name);
    onRoomStateSub[name]?.cancel();
    onRoomStateSub.remove(name);
    onSyncSub[name]?.cancel();
    onSyncSub.remove(name);
  }

  void initMatrix() {
    for (final c in widget.clients) {
      _registerSubs(c.clientName);
    }

    if (PlatformInfos.isMobile) {
      backgroundPush = BackgroundPush(
        this,
        onFcmError: (errorMsg, {Uri? link}) async {
          final context =
              FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
              this.context;
          if (!context.mounted) return;
          // final result = await showOkCancelAlertDialog(
          //   context: context,
          //   title: L10n.of(context).pushNotificationsNotAvailable,
          //   message: errorMsg,
          //   okLabel: link == null
          //       ? L10n.of(context).ok
          //       : L10n.of(context).learnMore,
          //   cancelLabel: L10n.of(context).doNotShowAgain,
          // );
          // if (result == OkCancelResult.ok && link != null) {
          //   launchUrlString(
          //     link.toString(),
          //     mode: LaunchMode.externalApplication,
          //   );
          // }
          // if (result == OkCancelResult.cancel) {
          //   await AppSettings.showNoGoogle.setItem(true);
          // }
        },
      );
    }
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    for (final client in widget.clients) {
      client.syncPresence = state == AppLifecycleState.resumed
          ? null
          : PresenceType.unavailable;
      if (PlatformInfos.isMobile) {
        client.backgroundSync = foreground;
        client.requestHistoryOnLimitedTimeline = !foreground;
        Logs().v('Set background sync to', foreground);
      }
    }
  }

  @override
  void dispose() {
    _listener?.dispose();

    for (final sub in onRoomKeyRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onKeyVerificationRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onLogoutSub.values) {
      sub.cancel();
    }
    for (final sub in onNotification.values) {
      sub.cancel();
    }
    for (final sub in onUiaRequest.values) {
      sub.cancel();
    }
    onRoomKeyRequestSub.clear();
    onKeyVerificationRequestSub.clear();
    onLogoutSub.clear();
    onNotification.clear();
    onUiaRequest.clear();

    voiceMessageEventId.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(create: (_) => this, child: widget.child);
  }

  Future<void> dehydrateAction(BuildContext context) async {
    final l10n = L10n.of(context);
    final response = await showOkCancelAlertDialog(
      context: context,
      isDestructive: true,
      title: l10n.dehydrate,
      message: l10n.dehydrateWarning,
    );
    if (response != OkCancelResult.ok) {
      return;
    }
    if (!context.mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: client.exportDump,
    );
    final export = result.result;
    if (export == null) return;

    final exportBytes = Uint8List.fromList(const Utf8Codec().encode(export));

    final exportFileName =
        'fluffychat-export-${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}.fluffybackup';

    final file = MatrixFile(bytes: exportBytes, name: exportFileName);
    if (!context.mounted) return;
    file.save(context);
  }
}

enum CallPosition { fullScreen, top }
