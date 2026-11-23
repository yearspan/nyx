import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/call/call_view_model.dart';
import 'package:fluffychat/pages/call/utils/get_call_tiles.dart';
import 'package:fluffychat/pages_v2/chat_v2/call/call_record_store.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/qr_code_viewer.dart';
import 'package:fluffychat/widgets_v2/invite_members_v2.dart';
import 'package:fluffychat/widgets_v2/v2_context_menu.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../widgets_v2/v2_app_bar.dart';

/// V2 1v1 语音/视频通话页（微信风格紫色 UI）。
///
/// 复用原版 [CallViewModel]（MatrixRTC / LiveKit，端到端加密）：
/// - 主叫：由 MatrixState.outgoingCallIntent 携带意图，自动发起呼叫
/// - 被叫：房间已有活跃通话时 VM 自动加入
/// - 通过 [CallOverlay] 承载：左上角「返回」缩成右上角迷你窗而不是挂断
class CallPageV2 extends StatefulWidget {
  final String roomId;

  const CallPageV2({super.key, required this.roomId});

  @override
  State<CallPageV2> createState() => _CallPageV2State();
}

class _CallPageV2State extends State<CallPageV2> {
  bool isDark = false;
  static const _gradient = //LinearGradient(colors: [Colors.black]):
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF8F69D5), Color(0xFF617ED6)],
  );

  late final Room room =
      Matrix.of(context).client.getRoomById(widget.roomId)!;

  late final CallViewModel _viewModel;
  Timer? _ticker;

  /// 对方加入 LiveKit 房间的时刻（通话真正开始计时）
  DateTime? _connectedAt;

  bool _ended = false;
  bool _failed = false;
  bool _recordSaved = false;
  Duration? _endedDuration;

  /// 控制栏（顶栏 + 底部按钮）是否可见。点击画面可切换。
  /// 仅首次进入且有远端视频时自动隐藏一次，之后纯靠点击切换。
  bool _controlsVisible = true;
  bool _autoHideTriggered = false;
  Timer? _controlsAutoHideTimer;

  /// 群聊中被放大全屏的 tile id；为 null 时显示宫格。
  String? _focusedTileId;

  /// 1v1 通话中检测到「无远端参与者」时的防抖计时器。
  /// 网络抖动/ICE 重连时远端参与者可能短暂从 remoteParticipants 消失，
  /// 若立即判定为对方挂断会导致通话误关闭。持续 3 秒仍无远端参与者
  /// 才认为对方真的挂断。
  Timer? _remoteGoneTimer;

  /// 监听被叫方拒绝接听的事件（org.matrix.msc4075.rtc.notification
  /// 携带 m.call.reject: true），收到后立即结束呼叫。
  StreamSubscription<Event>? _rejectEventSub;

  /// dispose 后置为 true，所有异步回调（定时器、postFrame 等）
  /// 调用 setState 前先检查，避免在已销毁的 Element 上 markNeedsBuild。
  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    final matrix = Matrix.of(context);
    final intentRaw = matrix.outgoingCallIntent;
    matrix.outgoingCallIntent = null;
    final intent = intentRaw == MatrixRtcCallIntent.video.name
        ? MatrixRtcCallIntent.video
        : intentRaw == MatrixRtcCallIntent.voice.name
        ? MatrixRtcCallIntent.voice
        : null;

    _viewModel = CallViewModel(room: room, initialIntent: intent);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed && mounted) setState(() {});
    });

    // 初始方向：1v1 允许横竖屏；群聊宫格默认锁定竖屏，只有放大某成员
    // 到全屏后才放开横屏（见 _updateOrientations）。
    _updateOrientations();

    // 1v1 主叫方：监听被叫方的拒绝事件，收到后立即结束呼叫，
    // 避免一直显示"呼叫中"。
    if (room.isDirectChat) {
      _rejectEventSub = room.client.onTimelineEvent.stream.listen((event) {
        if (_disposed || _ended) return;
        if (event.roomId != room.id) return;
        if (event.type != RtcNotificationContent.eventType) return;
        if (event.content.tryGet<bool>('m.call.reject') != true) return;
        // 被叫方拒绝，若通话尚未接通则按"未接"处理
        if (_connectedAt == null) {
          Logs().i('Callee rejected the call, ending call');
          _onCallError();
        }
      });
    }
  }

  /// 根据当前是否群聊全屏，动态控制允许的屏幕方向。
  /// - 1v1：始终允许横竖屏（观看对方屏幕共享时横过来更清楚）
  /// - 群聊宫格：仅竖屏，多人画面布局在横屏下会错乱
  /// - 群聊全屏：放开横屏，方便横屏观看放大的视频
  void _updateOrientations() {
    if (!PlatformInfos.isMobile) return;
    final isGroup = !room.isDirectChat;
    final allowLandscape = !isGroup || _focusedTileId != null;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      if (allowLandscape) ...[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _controlsAutoHideTimer?.cancel();
    _remoteGoneTimer?.cancel();
    _rejectEventSub?.cancel();
    // 兜底：未走结束按钮（如进程回收）时也尽量记录一次
    _persistCallRecord();
    _viewModel.dispose();
    // 退出通话后恢复仅竖屏，避免影响其他页面布局。
    if (PlatformInfos.isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    super.dispose();
  }

  // ---- 控制栏显隐 ----

  /// 切换控制栏（顶栏 + 底部按钮）显隐。纯手动切换，不再自动隐藏。
  void _toggleControlsVisibility() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
  }

  /// 首次检测到远端视频时，延迟几秒自动隐藏控制栏，仅触发一次。
  void _scheduleControlsAutoHide() {
    if (_autoHideTriggered) return;
    _autoHideTriggered = true;
    _controlsAutoHideTimer?.cancel();
    _controlsAutoHideTimer = Timer(const Duration(seconds: 4), () {
      if (!_disposed && mounted && _controlsVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  // ---- 通话控制 ----

  Future<void> _toggleMute() async {
    final local = _viewModel.value.room?.localParticipant;
    if (local != null) {
      await local.setMicrophoneEnabled(!local.isMicrophoneEnabled());
    } else {
      // 尚未进入 LiveKit 房间（连接中）：切换初始麦克风状态
      _viewModel.togglePreviewMic();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    final local = _viewModel.value.room?.localParticipant;
    if (local == null) return;
    await local.setCameraEnabled(!local.isCameraEnabled());
    // 开视频时切到扬声器，关视频保持用户当前选择
    if (PlatformInfos.isMobile && local.isCameraEnabled()) {
      await lk.AudioManager.instance.setSpeakerOutputPreferred(true);
    }
    if (mounted) setState(() {});
  }

  /// macOS 屏幕录制权限通道（见 macos/Runner/MainFlutterWindow.swift）。
  static const _screenPermissionChannel =
      MethodChannel('nexora/screen_permission');

  /// 切换屏幕共享（仅 web/桌面端；移动端不支持）。
  Future<void> _toggleScreenShare() async {
    final local = _viewModel.value.room?.localParticipant;
    if (local == null) return;
    final next = !local.isScreenShareEnabled();
    Logs().d(
      '[CallDebug] toggleScreenShare next=$next '
      'currentEnabled=${local.isScreenShareEnabled()}',
    );

    // 开启屏幕共享前，macOS 必须先获得「屏幕录制」权限。
    // 若用户拒绝了 TCC，ScreenCaptureKit 无法采集画面，但 livekit_client
    // 仍会发布一条无帧的轨道，结果是对端黑屏、本端按钮卡在「停止共享」。
    // 这里在调用 setScreenShareEnabled 之前主动校验权限，被拒时直接提示
    // 并返回，不进入「共享中」状态。
    if (next && PlatformInfos.isMacOS) {
      final granted = await _ensureMacOSScreenCapturePermission();
      if (!granted) {
        if (mounted) setState(() {});
        return;
      }
    }

    // Windows 端 flutter_webrtc 的 getDisplayMedia 内部依赖一个预先枚举好
    // 的桌面源列表（native sources_）。若从未调用过 getSources，该列表为空，
    // getDisplayMedia 会直接抛出 "source not found!"。这里在开启共享前先枚举
    // 一次屏幕源，确保默认源（id="0"，主屏）存在。
    if (next && PlatformInfos.isWindows) {
      try {
        await rtc.desktopCapturer.getSources(
          types: [rtc.SourceType.Screen],
        );
      } catch (e) {
        Logs().e('[CallDebug] pre-enumerate desktop sources failed', e);
      }
    }

    try {
      await local.setScreenShareEnabled(next);
      final pub = local.getTrackPublicationBySource(
        lk.TrackSource.screenShareVideo,
      );
      Logs().d(
        '[CallDebug] toggleScreenShare done. enabled=${local.isScreenShareEnabled()} '
        'pubSid=${pub?.sid} pubMuted=${pub?.muted} track=${pub?.track?.sid ?? 'null'}',
      );
      // 开启后二次确认：若轨道为空或已静音，说明采集失败（如系统弹窗被取消），
      // 回退状态并提示，避免按钮卡在「停止共享」。
      if (next && (pub == null || pub.muted)) {
        Logs().e(
          '[CallDebug] screen share track missing/muted after enable, '
          'rolling back. pub=${pub?.sid} muted=${pub?.muted}',
        );
        await local.setScreenShareEnabled(false);
        V2Toast.show('屏幕共享启动失败，请重试');
      }
    } catch (e, s) {
      // 用户取消选择屏幕窗口等情况会抛异常
      Logs().e('[CallDebug] toggleScreenShare failed', e, s);
      V2Toast.show('屏幕共享已取消');
    }
    if (mounted) setState(() {});
  }

  /// 检查并请求 macOS 屏幕录制权限。返回是否已授权。
  Future<bool> _ensureMacOSScreenCapturePermission() async {
    try {
      final granted = await _screenPermissionChannel
          .invokeMethod<bool>('checkScreenCapturePermission');
      Logs().d('[CallDebug] screenCapture preflight=$granted');
      if (granted == true) return true;

      final result = await _screenPermissionChannel
          .invokeMethod<bool>('requestScreenCapturePermission');
      Logs().d('[CallDebug] screenCapture request result=$result');
      if (result == true) return true;

      // 已被拒绝过，系统不再弹窗。直接打开「系统设置 → 屏幕录制」面板，
      // 让用户手动勾选 NYX。
      try {
        await _screenPermissionChannel
            .invokeMethod<void>('openScreenCaptureSettings');
      } catch (_) {}
      V2Toast.show(
        '请在系统设置的「屏幕录制」中允许 NYX，然后重启应用',
      );
      return false;
    } on PlatformException catch (e) {
      Logs().e('[CallDebug] screenCapture permission channel error', e);
      V2Toast.show('无法检查屏幕录制权限，请在系统设置中手动开启');
      return false;
    } catch (e) {
      Logs().e('[CallDebug] screenCapture permission unexpected error', e);
      return false;
    }
  }

  Future<void> _switchCamera() async {
    final local = _viewModel.value.room?.localParticipant;
    if (local == null) return;
    final track = local.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;
    if (PlatformInfos.isMobile) {
      // 移动端直接切换前后摄像头，无需 deviceId
      await rtc.Helper.switchCamera(track.mediaStreamTrack);
    } else {
      // 桌面端：枚举视频输入设备并切换到下一个
      final videoDevices = await lk.Hardware.instance.videoInputs();
      if (videoDevices.length < 2) return;
      final currentId =
          _viewModel.value.room?.roomOptions.defaultCameraCaptureOptions
              .deviceId;
      final currentIndex = videoDevices.indexWhere(
        (d) => d.deviceId == currentId,
      );
      final nextDevice =
          videoDevices[(currentIndex + 1) % videoDevices.length];
      await _viewModel.value.room?.setVideoInputDevice(nextDevice);
    }
  }

  Future<void> _hangUp() async {
    if (_ended) return;
    setState(() {
      _ended = true;
      _endedDuration = _connectedAt == null
          ? null
          : DateTime.now().difference(_connectedAt!);
    });
    _persistCallRecord();
    unawaited(_silentLeave());
    // 展示「通话结束」片刻后关闭
    Future.delayed(const Duration(milliseconds: 1400), _closeCall);
  }

  /// 对方挂断：进入结束态并稍后关闭
  Future<void> _remoteHungUp([Object? _]) async {
    if (_ended || _connectedAt == null || !mounted) return;
    setState(() {
      _ended = true;
      _endedDuration = DateTime.now().difference(_connectedAt!);
    });
    _persistCallRecord();
    unawaited(_silentLeave());
    Future.delayed(const Duration(milliseconds: 1400), _closeCall);
  }

  /// 呼叫失败：展示「呼叫失败」片刻后关闭
  Future<void> _onCallError([Object? _]) async {
    if (_ended || _failed || !mounted) return;
    setState(() {
      _failed = true;
      _ended = true;
    });
    _persistCallRecord();
    unawaited(_silentLeave());
    Future.delayed(const Duration(milliseconds: 1600), _closeCall);
  }

  /// 把本通通话结果（接通时长 / 未接 / 已取消）写入本地通话记录，
  /// 时间线里的振铃事件据此渲染成通话记录气泡
  void _persistCallRecord() {
    if (_recordSaved) return;
    _recordSaved = true;

    final matrix = Matrix.of(context);
    final outgoingRingId = _viewModel.ringEventId;
    final incomingRingId = matrix.incomingCallRingEventId;
    matrix.incomingCallRingEventId = null;
    final ringEventId = outgoingRingId ?? incomingRingId;
    if (ringEventId == null) return;

    final connected = _connectedAt != null;
    final isVideo =
        _viewModel.initialIntent == MatrixRtcCallIntent.video ||
        room.activeMatrixRtcCallIntent == MatrixRtcCallIntent.video;

    unawaited(
      CallRecordStore.instance.save(
        ringEventId: ringEventId,
        outcome: connected
            ? CallRecordOutcome.answered
            : outgoingRingId != null
            ? CallRecordOutcome.cancelled
            : CallRecordOutcome.missed,
        duration: connected
            ? DateTime.now().difference(_connectedAt!)
            : Duration.zero,
        isVideo: isVideo,
      ),
    );
  }

  /// 静默退出 MatrixRTC 会话；不再弹原版的 loading 对话框
  Future<void> _silentLeave() async {
    try {
      final liveKitRoom = _viewModel.value.room;
      if (liveKitRoom != null &&
          liveKitRoom.connectionState != lk.ConnectionState.disconnected) {
        await liveKitRoom.disconnect();
      }
      if (room.ownMatrixRtcMembership != null) {
        await room.leaveMatrixRtcCall();
      }
    } catch (_) {
      // dispose() 里还会再兜底清理一次
    }
  }

  void _closeCall() {
    if (mounted) {
      Matrix.of(context).activeCallRoomId.value = null;
    }
  }

  void _onBack() {
    if (_ended || _viewModel.value.error != null) {
      _closeCall();
      return;
    }
    // 通话中返回：缩成迷你悬浮窗，通话继续
    Matrix.of(context).callPosition.value = CallPosition.top;
  }

  // ---- 渲染 ----

  @override
  Widget build(BuildContext context) {
    isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<CallPosition>(
      valueListenable: Matrix.of(context).callPosition,
      builder: (context, position, _) {
        if (position != CallPosition.fullScreen) {
          return _buildMini();
        }
        return _buildFullScreen();
      },
    );
  }

  Widget _buildFullScreen() {
    final l10n = L10n.of(context);
    return Scaffold(
      body: AnimatedBuilder(
        animation: _viewModel,
        builder: (context, _) {
          final state = _viewModel.value;
          final liveKitRoom = state.room;
          final local = liveKitRoom?.localParticipant;
          final remotes = liveKitRoom?.remoteParticipants.values ??
              const <lk.RemoteParticipant>[];
          final hasRemote = remotes.isNotEmpty;
          final isGroup = !room.isDirectChat;

          // [调试] 远端视频轨状态，定位屏幕共享不显示
          if (remotes.isNotEmpty) {
            for (final p in remotes) {
              for (final pub in p.videoTrackPublications) {
                Logs().d(
                  '[CallDebug] remote participant=${p.identity} '
                  'pub=${pub.name} sid=${pub.sid} isScreenShare=${pub.isScreenShare} '
                  'muted=${pub.muted} subscribed=${pub.subscribed} '
                  'subscriptionAllowed=${pub.subscriptionAllowed} '
                  'track=${pub.track?.sid ?? 'null'} '
                  'streamState=${pub.track != null ? pub.streamState.name : 'n/a'}',
                );
              }
            }
          }
          // 群聊：成员以 Matrix RTC 状态为准（含正在加入 SFU 的人）
          final rawTiles = isGroup
              ? (liveKitRoom?.getCallTiles(room) ?? const <TileData>[])
              : const <TileData>[];
          final tiles = isGroup ? _dedupeTiles(rawTiles) : rawTiles;
          final hasCompanion =
              isGroup ? tiles.any((tile) => tile.connected) : hasRemote;

          if (hasCompanion && _connectedAt == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_disposed && mounted && _connectedAt == null && !_ended) {
                setState(() => _connectedAt = DateTime.now());
              }
            });
          }
          // 仅 1v1：对方离开 = 对方挂断。群聊成员进出不结束通话。
          // 加 3 秒防抖：网络抖动/ICE 重连时远端参与者可能短暂从
          // remoteParticipants 消失，立即判定会误关通话。
          if (!isGroup && _connectedAt != null && !_ended) {
            if (hasRemote) {
              _remoteGoneTimer?.cancel();
              _remoteGoneTimer = null;
            } else if (_remoteGoneTimer == null) {
              _remoteGoneTimer = Timer(const Duration(seconds: 3), () {
                if (!_disposed && mounted && !_ended) {
                  _remoteHungUp();
                }
              });
            }
          }
          // 建立通话失败
          if (state.error != null && !_ended && !_failed) {
            WidgetsBinding.instance.addPostFrameCallback(_onCallError);
          }

          final micOn = local == null
              ? state.startWithAudio
              : local.isMicrophoneEnabled();
          final cameraOn = local?.isCameraEnabled() ??
              (state.localVideoTrack?.muted == false);
          final screenSharing = local?.isScreenShareEnabled() == true;

          final remotePublication = isGroup
              ? null
              : _firstActiveRemoteVideoPublication(remotes);
          final remoteVideo = remotePublication?.track;
          // 屏幕共享是横屏内容，手机竖屏用 cover 会裁剪掉两侧只留中间。
          // 因此屏幕共享轨用 contain（完整画面+黑边），摄像头轨保持 cover。
          final remoteIsScreenShare = remotePublication?.isScreenShare ?? false;
          final remoteFit = remoteIsScreenShare
              ? lk.VideoViewFit.contain
              : lk.VideoViewFit.cover;
          Logs().d(
            '[CallDebug] isGroup=$isGroup hasRemote=$hasRemote '
            'remoteCount=${remotes.length} '
            'remoteVideo=${remoteVideo?.sid ?? 'null'} '
            'remoteVideoMuted=${remoteVideo?.muted} '
            'remoteIsScreenShare=$remoteIsScreenShare',
          );
          if (!hasRemote) {
            Logs().d(
              '[CallDebug] no remote participants. '
              'lkRoomName=${liveKitRoom?.name ?? '(not connected)'} '
              'connectionState=${liveKitRoom?.connectionState.name}',
            );
          }
          // 首次检测到远端视频时，自动隐藏控制栏一次，之后纯靠点击切换。
          if (remoteVideo != null && !_autoHideTriggered) {
            _scheduleControlsAutoHide();
          }
          // 1v1 全屏：显式订阅最高画质层。仅依赖 adaptiveStream 的渲染尺寸
          // 推断时，部分机型/旧版 SFU 在竖屏下可能选错中间层（360p），
          // 表现为对方画面明显模糊。缩成迷你窗后 adaptiveStream 仍会自动
          // 用小尺寸覆盖该设置，不会浪费流量。
          // 主动保证屏幕共享轨可用（1v1 与群聊均适用）。对方在通话中才
          // 开始共享时，该轨可能被 adaptiveStream 暂停甚至退订（track 为
          // null），导致手机端看不到桌面。这里无条件对远端屏幕共享轨执行
          // subscribe()+enable()，并设为最高画质，确保桌面画面清晰送达。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _ended) return;
            for (final participant in remotes) {
              for (final pub in participant.videoTrackPublications) {
                if (!pub.isScreenShare) continue;
                Logs().d(
                  '[CallDebug] ensureScreenShare sid=${pub.sid} '
                  'subscribed=${pub.subscribed} muted=${pub.muted} '
                  'track=${pub.track?.sid ?? 'null'} '
                  'streamState=${pub.streamState.name}',
                );
                if (pub.subscribed) {
                  pub.enable();
                  if (pub.videoQuality != lk.VideoQuality.HIGH) {
                    pub.setVideoQuality(lk.VideoQuality.HIGH);
                  }
                  Logs().d(
                    '[CallDebug] screenShare enable() + HIGH called',
                  );
                } else {
                  Logs().d(
                    '[CallDebug] screenShare not subscribed, subscribing...',
                  );
                  pub.subscribe().then((_) {
                    Logs().d(
                      '[CallDebug] screenShare subscribe done, enabling. '
                      'subscribed=${pub.subscribed}',
                    );
                    pub.enable();
                    pub.setVideoQuality(lk.VideoQuality.HIGH);
                  });
                }
              }
            }
          });

          if (!isGroup && remoteVideo != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _ended) return;
              final publication = _firstActiveRemoteVideoPublication(
                remotes,
              );
              if (publication == null) return;
              // 屏幕共享轨的启用已由上方逻辑处理；这里只对摄像头轨提升到
              // 最高画质，避免竖屏下被选成 360p 中间层。
              // 用 setVideoDimensions 而非 setVideoQuality(HIGH)：后者依赖
              // 服务端下发的 layer 尺寸信息，极端情况下 layer 信息缺失会
              // 导致 resolveVideoSettings 退化为只用 adaptiveStream 上报尺寸。
              // 直接指定 1920x1080 更稳妥，配合上方 fixed(3.0) 的像素密度
              // 上报，adaptiveStream 不会把它覆盖成更小的尺寸。
              const desired = lk.VideoDimensions(1920, 1080);
              if (!publication.isScreenShare &&
                  publication.videoDimensions != desired) {
                publication.setVideoDimensions(desired);
              }
            });
          }
          final localPublications = local?.videoTrackPublications;
          final localVideo = localPublications != null
              ? _firstActiveVideoTrack(localPublications)
              : (state.localVideoTrack != null &&
                        !state.localVideoTrack!.muted
                    ? state.localVideoTrack
                    : null);

          return DecoratedBox(
            decoration: BoxDecoration(gradient: isDark? LinearGradient(colors: [Colors.black,Colors.black]) :_gradient),
            child: Stack(
              children: [
                // 1v1：对方视频铺满背景
                if (!isGroup && remoteVideo != null)
                  Positioned.fill(
                    child: lk.VideoTrackRenderer(
                      remoteVideo,
                      fit: remoteFit,
                      // 固定 3x 像素密度上报给 adaptiveStream：低 DPR 设备
                      // （如 iPhone SE DPR=2）按实际密度上报的物理像素面积
                      // 会小于 1080p，导致 SFU 只下发 720p 甚至 360p 层，
                      // 对方画面明显模糊。固定 3x 后上报尺寸恒大于 1080p，
                      // 配合下方 setVideoDimensions(1920x1080) 确保拿到高层。
                      adaptiveStreamPixelDensity:
                          const lk.AdaptiveStreamPixelDensity.fixed(3.0),
                    ),
                  ),
                // 1v1：点击画面任意位置切换控制栏显隐。
                // 放在视频之上、控制栏之下；控制栏中间区域已用 IgnorePointer
                // 放行，所以点中间空白/状态文本也能切换，不再只有点视频
                // 未被遮挡的窄缝才生效。
                if (!isGroup)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControlsVisibility,
                    ),
                  ),
                if (!isGroup && remoteVideo != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 220,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.45),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                // 顶栏 + 底部控制栏：淡入淡出，隐藏时不拦截点击
                IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: SafeArea(
                      child: Column(
                        children: [
                          _buildTopBar(l10n.back),
                          if (isGroup)
                            _buildGroupHeader(l10n, tiles, state.error)
                          else
                            SizedBox(height: 4),
                          Expanded(
                            // 1v1 时中间区域纯展示（状态文本/头像），
                            // 不拦截点击，让点击穿透到底层切换控制栏
                            // 显隐的 GestureDetector；群聊时中间是宫格
                            // 视频，需要可点击，不包裹 IgnorePointer。
                            child: isGroup
                                ? Center(child: _buildGroupStage(tiles))
                                : IgnorePointer(
                                    ignoring: true,
                                    child: Center(
                                      child: remoteVideo == null
                                          ? _buildAvatarBlock(
                                              context,
                                              hasRemote: hasRemote,
                                              error: state.error,
                                            )
                                          : _buildVideoStatus(
                                              context,
                                              hasRemote: hasRemote,
                                            ),
                                    ),
                                  ),
                          ),
                          // 「未开启麦克风」提示
                          if (!_ended && !micOn)
                            Container(
                              margin: EdgeInsets.only(bottom: 18),
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.mic_off,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    l10n.microphoneOffHint,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _buildControls(
                            micOn: micOn,
                            cameraOn: cameraOn,
                            screenSharing: screenSharing,
                          ),
                          SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ),
                // 本地视频小窗（仅 1v1；群聊自己出现在宫格中）
                if (!isGroup && localVideo != null)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 56,
                    right: 16,
                    child: GestureDetector(
                      onTap: _toggleCamera,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 96,
                          height: 140,
                          child: lk.VideoTrackRenderer(
                            localVideo,
                            mirrorMode: lk.VideoViewMirrorMode.mirror,
                            fit: lk.VideoViewFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 群聊全屏：覆盖整个屏幕，仅显示视频 + 右上角缩小按钮。
                // 放在 Stack 最顶层，盖住顶栏/底栏/宫格，实现真正的全屏。
                if (isGroup && _focusedTileId != null)
                  Positioned.fill(
                    child: _buildGroupFocusedTile(
                      tiles.firstWhereOrNull(
                        (t) => t.id == _focusedTileId,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 迷你悬浮窗（通话中按返回）
  Widget _buildMini() {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final liveKitRoom = _viewModel.value.room;
        final hasRemote =
            liveKitRoom?.remoteParticipants.isNotEmpty ?? false;
        final name = _displayName();
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: isDark? LinearGradient(colors: [Colors.black,Colors.black]) :_gradient),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Matrix.of(context).callPosition.value =
                    CallPosition.fullScreen;
              },
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _avatar(size: 46, ring: false),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          _statusText(
                            context,
                            hasRemote: hasRemote,
                            error: _viewModel.value.error,
                            mini: true,
                          ),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: _hangUp,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(String backLabel) {
    final l10n = L10n.of(context);
    final isGroup = !room.isDirectChat;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          alignment: Alignment.centerLeft,
          margin: EdgeInsets.only(left: 12),
          child: V2CircleIconButton(
            icon: Icons.chevron_left,
            iconColor: Theme.of(context).colorScheme.onSurface,
            onTap: _onBack,
          ),
        ),
        if (isGroup)
          GestureDetector(
            onTapDown: (details) => _showMoreMenu(details.globalPosition),
            child: Container(
                margin: EdgeInsets.only(right: 12),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: V2Theme.of(context).cardBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    Icons.more_horiz, size: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
          )
      ],
    );
  }

  /// 右上角 more 菜单：添加成员 / 通过链接邀请
  Future<void> _showMoreMenu(Offset position) async {
    final l10n = L10n.of(context);
    final selected = await V2ContextMenu.show(
      context,
      position: position,
      items: [
        V2ContextMenuItem(
          label: l10n.addMembers,
          icon: Icons.person_add_outlined,
        ),
        V2ContextMenuItem(
          label: l10n.inviteViaLink,
          icon: Icons.link,
        ),
      ],
    );
    Logs().i("showmore::$selected");
    if (selected == null || !mounted) return;

    if (selected.label == l10n.addMembers) {
      await InviteMembersV2.show(context, roomId: room.id);
    } else if (selected.label == l10n.inviteViaLink) {
      final alias = room.canonicalAlias;
      if (alias.isNotEmpty) {
        showQrCodeViewer(context, alias);
      } else {
        showQrCodeViewer(context, room.id);
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text(l10n.noInviteLink)),
        // );
      }
    }
  }

  // ---- 群聊通话：头部 + 多人舞台 ----

  /// 群聊头部：群名 + 通话类型/人数/计时 + 等待或结束状态
  Widget _buildGroupHeader(
    L10n l10n,
    List<TileData> tiles,
    Object? error,
  ) {
    final isVideo = room.activeMatrixRtcCallIntent ==
            MatrixRtcCallIntent.video ||
        _viewModel.initialIntent == MatrixRtcCallIntent.video;
    final infoStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.75),
      fontSize: 13,
    );

    final String statusLine;
    if (_ended) {
      statusLine = _failed
          ? _callErrorText(l10n, error)
          : l10n.callEnded;
    } else if (error != null) {
      statusLine = _callErrorText(l10n, error);
    } else if (_connectedAt != null) {
      statusLine =
          '${l10n.callParticipantsCount(tiles.length)} · ${_formatDuration(
        DateTime.now().difference(_connectedAt!),
      )}';
    } else if (_viewModel.value.isLoading ||
        _viewModel.value.room == null) {
      statusLine = l10n.callConnecting;
    } else {
      statusLine = l10n.waitingForParticipants;
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _displayName(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVideo ? Icons.videocam : Icons.call,
                size: 14,
                color: Colors.white70,
              ),
              SizedBox(width: 5),
              Text(statusLine, style: infoStyle),
            ],
          ),
          if (_ended && _endedDuration != null) ...[
            SizedBox(height: 4),
            Text(
              _formatDuration(_endedDuration!),
              style: infoStyle,
            ),
          ],
        ],
      ),
    );
  }

  /// 群聊舞台：有人开摄像头 → 视频宫格；否则 → 语音头像区。
  /// 全屏视图由最外层 Stack 单独渲染，不在这里处理。
  /// 注意：tiles 已经在 _buildFullScreen 里做过 _dedupeTiles，这里直接用，
  /// 避免重复去重产生新的 List 实例，影响 Key 匹配。
  Widget _buildGroupStage(List<TileData> tiles) {
    final hasCamera = tiles.any((tile) => tile.video != null);
    if (!hasCamera) {
      return _buildGroupVoiceStage(tiles);
    }
    return _buildGroupVideoGrid(tiles);
  }

  /// 每个成员只保留一个 tile：优先屏幕共享轨道（用户共享桌面就是为了
  /// 让其他人看），否则用摄像头轨道。
  /// 摄像头关闭/静音的视频轨回退为头像占位。
  List<TileData> _dedupeTiles(List<TileData> tiles) {
    final perUser = <String, TileData>{};
    for (final tile in tiles) {
      final pub = tile.video;
      final isScreenShare = pub?.isScreenShare ?? false;
      final hasVideo = pub != null && pub.track?.muted == false;
      final effectiveVideo = hasVideo ? pub : null;
      final effective = (
        id: tile.id,
        participantId: tile.participantId,
        video: effectiveVideo,
        audio: tile.audio,
        user: tile.user,
        connected: tile.connected,
        isSpeaking: tile.isSpeaking,
      );
      final existing = perUser[tile.user.id];
      if (existing == null) {
        perUser[tile.user.id] = effective;
      } else {
        final existingPub = existing.video;
        final existingIsScreen = existingPub?.isScreenShare ?? false;
        final existingHasVideo =
            existingPub != null && existingPub.track?.muted == false;
        // 屏幕共享优先于摄像头：用户共享屏幕就是为了让其他人看，
        // 若同时开摄像头，应显示屏幕共享而非摄像头画面。
        // 已有屏幕共享时不被摄像头覆盖；已有摄像头时被屏幕共享替换。
        if (existingHasVideo && existingIsScreen && !isScreenShare) continue;
        if (effectiveVideo != null &&
            (!existingHasVideo ||
                (isScreenShare && !existingIsScreen))) {
          perUser[tile.user.id] = effective;
        }
      }
    }
    return perUser.values.toList();
  }

  /// 语音群通话：头像 Wrap，正在说话的人绿色光环
  Widget _buildGroupVoiceStage(List<TileData> tiles) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 18,
          runSpacing: 22,
          alignment: WrapAlignment.center,
          children: [
            for (final tile in tiles)
              SizedBox(
                key: ValueKey(tile.id),
                width: 78,
                child: Opacity(
                  opacity: tile.connected ? 1 : 0.55,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: tile.isSpeaking
                              ? Border.all(
                                  color: Color(0xFF07C160),
                                  width: 3,
                                )
                              : null,
                        ),
                        padding: EdgeInsets.all(2),
                        child: ClipOval(
                          child: Avatar(
                            mxContent: tile.user.avatarUrl,
                            name: tile.user.calcDisplayname(),
                            size: 68,
                          ),
                        ),
                      ),
                      SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_viewModel.isAdmin &&
                              tile.user.id != room.client.userID)
                            GestureDetector(
                              onTap: () {
                                final muted = tile.audio == null ||
                                    tile.audio!.muted == true;
                                final pid = tile.participantId;
                                if (pid != null) {
                                  _viewModel.remoteMuteParticipant(
                                    pid,
                                    !muted,
                                  );
                                }
                              },
                              child: Icon(
                                (tile.audio == null ||
                                        tile.audio!.muted == true)
                                    ? Icons.mic_off
                                    : Icons.mic_none,
                                size: 12,
                                color: (tile.audio == null ||
                                        tile.audio!.muted == true)
                                    ? Colors.white70
                                    : Colors.white,
                              ),
                            )
                          else if (tile.audio == null ||
                              tile.audio!.muted == true)
                            Icon(
                              Icons.mic_off,
                              size: 12,
                              color: Colors.white70,
                            ),
                          SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              tile.user.calcDisplayname(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
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

  /// 视频群通话：自适应宫格（1人1列、≤4人2列、更多3列）
  Widget _buildGroupVideoGrid(List<TileData> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = tiles.length;
        final cross = count <= 1 ? 1 : (count <= 4 ? 2 : 3);
        const spacing = 6.0;
        const padding = 12.0;
        final tileWidth =
            (constraints.maxWidth - padding * 2 - spacing * (cross - 1)) /
            cross;
        final rows = (count / cross).ceil();
        final tileHeight =
            (constraints.maxHeight - spacing * (rows - 1)) / rows;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: padding,
            vertical: 4,
          ),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final tile in tiles)
                SizedBox(
                  key: ValueKey(tile.id),
                  width: tileWidth,
                  height: tileHeight.clamp(140.0, 260.0),
                  child: _GroupVideoTile(
                    tile: tile,
                    isOwn: tile.user.id == room.client.userID,
                    canRemoteMute: _viewModel.isAdmin &&
                        tile.user.id != room.client.userID,
                    onTap: () {
                      if (_disposed || !mounted) return;
                      setState(() => _focusedTileId = tile.id);
                      _updateOrientations();
                    },
                    onRemoteMute: (muted) {
                      final pid = tile.participantId;
                      if (pid != null) {
                        _viewModel.remoteMuteParticipant(pid, muted);
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 群聊中选中某成员后的全屏视频视图。
  /// 真正的全屏：仅视频铺满 + 右上角缩小按钮，无顶栏/底栏/姓名栏。
  /// tile 可能为 null（横屏重建时 tile 列表短暂缺失），此时显示黑色占位，
  /// 不清除 _focusedTileId，等 tile 回来自动恢复，避免横屏后全屏消失。
  Widget _buildGroupFocusedTile(TileData? tile) {
    final track = tile?.video?.track;
    final isOwn = tile?.user.id == room.client.userID;
    final isScreenShare = tile?.video?.isScreenShare ?? false;
    final fit = isScreenShare
        ? lk.VideoViewFit.contain
        : lk.VideoViewFit.cover;
    final name = tile?.user.calcDisplayname();

    return Stack(
      fit: StackFit.expand,
      children: [
        // 黑色背景：铺满全屏，盖住底层的顶栏/底栏/宫格。
        // 屏幕共享用 contain 时视频上下有空白，若无此背景会透出底层控件。
        const DecoratedBox(decoration: BoxDecoration(color: Colors.black)),
        // 视频 / 头像 / 加载占位
        if (track != null)
          lk.VideoTrackRenderer(
            track,
            fit: fit,
            mirrorMode: isOwn
                ? lk.VideoViewMirrorMode.mirror
                : lk.VideoViewMirrorMode.off,
            // 全屏固定 3x 密度上报，确保拿到最高画质层
            adaptiveStreamPixelDensity:
                const lk.AdaptiveStreamPixelDensity.fixed(3.0),
          )
        else
          Center(
            child: tile == null
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white70,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipOval(
                        child: Avatar(
                          mxContent: tile.user.avatarUrl,
                          name: name ?? '',
                          size: 96,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
          ),
        // 右上角缩小按钮：唯一可见控件，点击退回宫格
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: V2CircleIconButton(
                  icon: Icons.close_fullscreen_rounded,
                  onTap: () {
                      if (_disposed || !mounted) return;
                        setState(() => _focusedTileId = null);
                        _updateOrientations();
                      },
            ),
          ),
        ),
      ],
    );
  }

  // ---- 头像 + 名称 + 状态 ----

  String _displayName() {
    final l10n = L10n.of(context);
    return room.getLocalizedDisplayname(MatrixLocals(l10n));
  }

  Widget _avatar({double size = 96, bool ring = true}) {
    // 群聊用房间头像；私聊用对方头像
    final otherId = room.directChatMatrixID;
    final user = otherId == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(otherId);
    final avatar = Avatar(
      mxContent: room.isDirectChat ? user?.avatarUrl : room.avatar,
      name: _displayName(),
      size: size,
    );
    if (!ring) {
      return ClipOval(child: avatar);
    }
    // 白圈头像 + 两层半透明光环
    return Container(
      width: size + 52,
      height: size + 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
      ),
      padding: EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.25),
        ),
        padding: EdgeInsets.all(10),
        child: ClipOval(child: avatar),
      ),
    );
  }

  Widget _buildAvatarBlock(
    BuildContext context, {
    required bool hasRemote,
    required Object? error,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _avatar(),
        SizedBox(height: 26),
        Text(
          _displayName(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 12),
        if (_ended) ...[
          Text(
            _failed
                ? _callErrorText(L10n.of(context), error)
                : L10n.of(context).callEnded,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (_endedDuration != null) ...[
            SizedBox(height: 6),
            Text(
              _formatDuration(_endedDuration!),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
              ),
            ),
          ],
        ] else if (hasRemote) ...[
          SizedBox(height: 8),
          _buildDurationChip(),
        ] else
          Text(
            _statusText(context, hasRemote: false, error: error),
            style: TextStyle(
              color: error != null
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
            ),
          ),
      ],
    );
  }

  /// 视频通话时顶部的状态：名称 + 计时/呼叫中
  Widget _buildVideoStatus(BuildContext context, {required bool hasRemote}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _displayName(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8),
        if (hasRemote)
          _buildDurationChip()
        else
          Text(
            _statusText(context, hasRemote: false, error: null),
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
      ],
    );
  }

  Widget _buildDurationChip() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.signal_cellular_alt, size: 15, color: Colors.white),
        SizedBox(width: 6),
        Text(
          // 对方刚加入的第一帧 _connectedAt 在下一帧才写入，回退为当前
          // 时刻显示 00:00，避免空指针
          _formatDuration(
            DateTime.now().difference(_connectedAt ?? DateTime.now()),
          ),
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  String _statusText(
    BuildContext context, {
    required bool hasRemote,
    required Object? error,
    bool mini = false,
  }) {
    final l10n = L10n.of(context);
    if (_ended) {
      return mini && _endedDuration != null
          ? _formatDuration(_endedDuration!)
          : l10n.callEnded;
    }
    if (error != null) return _callErrorText(l10n, error);
    if (!room.isDirectChat) {
      // 群聊：N 人在通话 + 计时；尚未有人加入时显示等待
      if (_connectedAt == null) {
        return _viewModel.value.isLoading || _viewModel.value.room == null
            ? l10n.callConnecting
            : l10n.waitingForParticipants;
      }
      final tiles = _viewModel.value.room?.getCallTiles(room) ??
          const <TileData>[];
      return '${l10n.callParticipantsCount(tiles.length)} · ${_formatDuration(
        DateTime.now().difference(_connectedAt!),
      )}';
    }
    if (hasRemote) {
      return _formatDuration(
        DateTime.now().difference(_connectedAt ?? DateTime.now()),
      );
    }
    return _viewModel.value.isLoading || _viewModel.value.room == null
        ? l10n.callConnecting
        : l10n.callRinging;
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 通话失败文案：权限不足时明确提示，其余显示通用「呼叫失败」
  String _callErrorText(L10n l10n, Object? error) =>
      error is MatrixRtcCallPermissionException
      ? l10n.callNotAllowedInRoom
      : l10n.callFailed;

  // ---- 底部控制按钮 ----

  Widget _buildControls({
    required bool micOn,
    required bool cameraOn,
    required bool screenSharing,
  }) {
    final l10n = L10n.of(context);
    final enabled = !_ended;
    final isVideo =
        _viewModel.initialIntent == MatrixRtcCallIntent.video ||
        room.activeMatrixRtcCallIntent == MatrixRtcCallIntent.video;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (isVideo)
          _controlButton(
            icon: Icons.flip_camera_ios_outlined,
            label: l10n.flipCamera,
            active: false,
            onTap: enabled ? _switchCamera : null,
          ),
        if (isVideo)
          _controlButton(
            icon: cameraOn ? Icons.videocam : Icons.videocam_off_outlined,
            label: l10n.video,
            active: cameraOn,
            // 无可用摄像头时按钮显示禁用态（不报错、不提示）
            onTap: enabled && _viewModel.cameraAvailable != false
                ? _toggleCamera
                : null,
          ),
        _controlButton(
          icon: micOn ? Icons.mic_none_outlined : Icons.mic_off,
          label: l10n.mute,
          active: micOn,
          // 无可用麦克风时按钮显示禁用态（不报错、不提示）
          onTap: enabled && _viewModel.microphoneAvailable != false
              ? _toggleMute
              : null,
        ),
        // 屏幕共享：仅 web / 桌面端支持，移动端无此能力
        if (!PlatformInfos.isMobile)
          _controlButton(
            icon: screenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share_outlined,
            label: screenSharing
                ? l10n.stopScreensharing
                : l10n.startScreensharing,
            active: screenSharing,
            onTap: enabled ? _toggleScreenShare : null,
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Material(
                color: Color(0xFFFF3B30)
                    .withValues(alpha: enabled ? 1 : 0.5),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? _hangUp : null,
                  child: Icon(Icons.close, color: Colors.white, size: 30),
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              l10n.end,
              style: TextStyle(
                color: Colors.white.withValues(alpha: enabled ? 0.87 : 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final background = !enabled
        ? Colors.white.withValues(alpha: 0.12)
        : active
        ? Colors.white
        : Colors.white.withValues(alpha: 0.22);
    final foreground = !enabled
        ? Colors.white.withValues(alpha: 0.5)
        : active
        ? Color(0xFF6A70E0)
        : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, size: 26, color: foreground),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: enabled ? 0.87 : 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// 从一组视频轨发布中取第一个「未静音」的有效轨道。
  /// 优先取屏幕共享轨：用户主动共享屏幕时，手机端应显示桌面画面而非摄像头；
  /// 若无屏幕共享轨则回退到摄像头轨。
  lk.VideoTrack? _firstActiveVideoTrack<T extends lk.VideoTrack>(
    Iterable<lk.TrackPublication<T>> publications,
  ) {
    lk.VideoTrack? cameraTrack;
    for (final publication in publications) {
      final track = publication.track;
      if (track == null || track.muted) continue;
      if (publication.isScreenShare) {
        return track;
      } else {
        cameraTrack ??= track;
      }
    }
    return cameraTrack;
  }

  /// 找到远端当前正在发送的视频轨道发布（跳过静音轨道）。
  /// 优先取屏幕共享轨；若没有则回退到摄像头轨。
  lk.RemoteTrackPublication<lk.RemoteVideoTrack>?
  _firstActiveRemoteVideoPublication(
    Iterable<lk.RemoteParticipant> participants,
  ) {
    lk.RemoteTrackPublication<lk.RemoteVideoTrack>? cameraPub;
    for (final participant in participants) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track == null || track.muted) continue;
        if (publication.isScreenShare) {
          return publication;
        } else {
          cameraPub ??= publication;
        }
      }
    }
    return cameraPub;
  }
}

/// 群聊视频宫格中的单个成员画面
class _GroupVideoTile extends StatelessWidget {
  final TileData tile;
  final bool isOwn;
  final bool canRemoteMute;
  final VoidCallback? onTap;
  final void Function(bool muted)? onRemoteMute;

  const _GroupVideoTile({
    required this.tile,
    required this.isOwn,
    this.canRemoteMute = false,
    this.onTap,
    this.onRemoteMute,
  });

  @override
  Widget build(BuildContext context) {
    final track = tile.video?.track;
    final muted = tile.audio == null || tile.audio!.muted == true;
    final name = tile.user.calcDisplayname();
    final isScreenShare = tile.video?.isScreenShare ?? false;
    // 屏幕共享是横屏内容，宫格中也用 contain 保留完整画面，避免裁剪。
    final fit = isScreenShare
        ? lk.VideoViewFit.contain
        : lk.VideoViewFit.cover;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0x99000000)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (track != null)
                lk.VideoTrackRenderer(
                  track,
                  fit: fit,
                  mirrorMode: isOwn
                      ? lk.VideoViewMirrorMode.mirror
                      : lk.VideoViewMirrorMode.off,
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipOval(
                        child: Avatar(
                          mxContent: tile.user.avatarUrl,
                          name: name,
                          size: 56,
                        ),
                      ),
                      SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // 底部姓名 + 麦克风状态
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Row(
                  children: [
                    if (canRemoteMute && onRemoteMute != null)
                      GestureDetector(
                        onTap: () => onRemoteMute!(!muted),
                        child: Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            muted ? Icons.mic_off : Icons.mic_none,
                            size: 13,
                            color:
                                muted ? Colors.white70 : Colors.white,
                          ),
                        ),
                      )
                    else if (muted)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.mic_off,
                          size: 13,
                          color: Colors.white70,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 尚未连上 SFU 的成员
            if (!tile.connected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  }
}
