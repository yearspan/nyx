import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/call_foreground_service.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/call_keys_event_content.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/position_from_build_context.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:just_audio/just_audio.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart' as logging;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 1v1 通话摄像头采集参数：1080p30。
///
/// 1v1 时对方大概率全屏观看，需要 1080p 保证清晰度。
const _cameraCaptureOptions1v1 = lk.CameraCaptureOptions(
  params: lk.VideoParametersPresets.h1080_169,
);

/// 群聊通话摄像头采集参数：720p20。
///
/// 群聊时手机发烫的主因是发送端同时编码多层 simulcast + 接收端多路
/// 解码 + 多视图渲染。群聊中自己的画面通常只占宫格一小格，720p 已
/// 足够；帧率降到 20fps 可进一步降低编解码 CPU 负载，且人眼对小画面
/// 帧率不敏感。
const _cameraCaptureOptionsGroup = lk.CameraCaptureOptions(
  params: lk.VideoParameters(
    dimensions: lk.VideoDimensions(1280, 720),
    encoding: lk.VideoEncoding(maxBitrate: 2000 * 1000, maxFramerate: 20),
  ),
);

/// 1v1 视频发布参数：simulcast 三层 180p / 720p / 1080p，高层 5 Mbps，H.264。
final _videoPublishOptions1v1 = lk.VideoPublishOptions(
  videoCodec: 'h264',
  videoEncoding: const lk.VideoEncoding(
    maxBitrate: 5000 * 1000,
    maxFramerate: 30,
  ),
  videoSimulcastLayers: const [
    lk.VideoParameters(
      dimensions: lk.VideoDimensions(320, 180),
      encoding: lk.VideoEncoding(maxBitrate: 300 * 1000, maxFramerate: 15),
    ),
    lk.VideoParameters(
      dimensions: lk.VideoDimensions(1280, 720),
      encoding: lk.VideoEncoding(maxBitrate: 2500 * 1000, maxFramerate: 30),
    ),
  ],
  degradationPreference: lk.DegradationPreference.maintainResolution,
);

/// 群聊视频发布参数：simulcast 两层 180p / 720p，高层 2 Mbps，H.264。
///
/// 相比 1v1 的优化：
/// 1. 去掉 1080p 高层：群聊中没人全屏看你，只发 180p + 720p 两层，
///    少编码一层，CPU 负载显著下降。
/// 2. 高层 720p 码率 2.5M → 2M：小宫格用不到太高码率。
/// 3. 帧率 30 → 20：与采集帧率一致，减少编码运算量。
final _videoPublishOptionsGroup = lk.VideoPublishOptions(
  videoCodec: 'h264',
  videoEncoding: const lk.VideoEncoding(
    maxBitrate: 2000 * 1000,
    maxFramerate: 20,
  ),
  videoSimulcastLayers: const [
    lk.VideoParameters(
      dimensions: lk.VideoDimensions(320, 180),
      encoding: lk.VideoEncoding(maxBitrate: 250 * 1000, maxFramerate: 15),
    ),
  ],
  degradationPreference: lk.DegradationPreference.maintainResolution,
);

class CallViewModelState {
  lk.Room? room;
  lk.LocalVideoTrack? localVideoTrack;
  bool startWithAudio = true;
  bool isLoading = false;
  Object? error;
  String? focusedTrack;
}

class CallViewModel extends ValueNotifier<CallViewModelState> {
  final Room room;
  Timeline? timeline;
  final AudioPlayer _audioPlayer = AudioPlayer();
  DateTime? startTime;
  StreamSubscription? _onCallEncryptionKeysSub, _onCallMembersChanged;
  Timer? _resendCallMemberState;

  /// debug 模式下每 5 秒输出视频收发统计，见 [_startVideoStatsDebug]。
  Timer? _statsDebugTimer;
  bool waitForOtherSide = false;

  /// 主叫发出的振铃事件 ID（被叫加入时为 null），用于通话记录持久化
  String? ringEventId;

  Set<String> _lastSharedParticipants = {};
  DateTime? _keyCreatedAt;
  Uint8List? _lastKey;

  lk.BaseKeyProvider? _keyProvider;

  /// 通话 E2EE（FrameCryptor）初始化失败时保存的异常，便于 UI 提示。
  /// 通常是 web 端缺失 e2ee.worker.dart.js 或浏览器不支持 Insertable Streams。
  Object? _e2eeInitError;

  /// 通话端到端加密是否可用（FrameCryptor 初始化成功）。
  bool get isCallE2eeAvailable => _keyProvider != null;

  /// 本机麦克风是否可用（采集成功）。不可用时通话页麦克风按钮显示禁用态。
  /// null 表示尚未探测。
  bool? microphoneAvailable;

  /// 本机摄像头是否可用（采集成功）。不可用时通话页摄像头按钮显示禁用态。
  /// null 表示尚未探测。
  bool? cameraAvailable;

  /// 主叫时的初始通话意图。为 null 时保持原行为（进入通话页预览摄像头，
  /// 手动点「开始通话」）；voice 时不创建摄像头采集，video 时创建并自动发起。
  final MatrixRtcCallIntent? initialIntent;

  CallViewModel({required this.room, this.initialIntent})
    : super(CallViewModelState()) {
    _init();
  }

  void setFocusedTrack(String trackId) {
    Logs().d('Set focus on', trackId);
    if (value.focusedTrack == trackId) {
      value.focusedTrack = null;
    } else {
      value.focusedTrack = trackId;
    }
    notifyListeners();
  }

  /// 管理员远程静音/取消静音某个参与者。通过 LiveKit 数据通道发送 mute 指令，
  /// 对方收到后执行本地静音。仅群主/管理员可调用。
  Future<void> remoteMuteParticipant(String participantId, bool muted) async {
    final local = value.room?.localParticipant;
    if (local == null) {
      Logs().w('[RemoteMute] cannot send: local participant is null');
      return;
    }
    Logs().d(
      '[RemoteMute] send to "$participantId" muted=$muted '
      '(valid identities: ${value.room?.remoteParticipants.keys.toList()})',
    );
    await local.publishData(
      utf8.encode(jsonEncode({'muted': muted})),
      destinationIdentities: [participantId],
      topic: 'mute',
      reliable: true,
    );
  }

  /// 当前用户是否为群主/管理员（power level >= 50）
  bool get isAdmin => room.ownPowerLevel.level >= 50;

  Future<void> _onCallEncryptionKeys(CallKeysEvent event) async {
    final callKeys = event.callKeysContent;
    final keyProvider = _keyProvider;
    if (keyProvider == null) {
      ErrorReporter(
        null,
        'Received a new key but the keyProvider is not ready yet!',
      ).onErrorCallback(Exception(), StackTrace.current);
      return;
    }

    final participantIdentity =
        '${event.sender}:${callKeys.member.claimedDeviceId}';
    await keyProvider.setRawKey(
      base64Decode(callKeys.keys.key),
      participantId: participantIdentity,
      keyIndex: callKeys.keys.index,
    );

    // 成员退出再加入时，接收端可能在收到该密钥前就已按旧的 key index
    // 建立了解密 cryptor（addRtpReceiver 默认取 getLatestIndex，可能为 0），
    // 导致一直用旧 index 解密新 index 的帧而黑屏。setRawKey 已更新
    // latestSetIndex，这里把该参与者所有已建立的 cryptor 同步到新 index。
    final liveKitRoom = value.room;
    if (liveKitRoom != null && liveKitRoom.e2eeManager != null) {
      await liveKitRoom.e2eeManager!.setKeyIndex(
        callKeys.keys.index,
        participantIdentity: participantIdentity,
      );
      Logs().d(
        '[CallKey] applied key index ${callKeys.keys.index} '
        'for "$participantIdentity"',
      );
    }
  }

  Future<void> _createKeyAndShare() async {
    final liveKitRoom = value.room;
    // E2EE 不可用时（如 web 端 FrameCryptor 初始化失败）跳过密钥分发，
    // 否则 roomOptions.encryption! 会抛 NPE。
    final encryption = liveKitRoom?.roomOptions.encryption;
    if (liveKitRoom == null || encryption == null) return;

    final ownMemberId = '${room.client.userID}:${room.client.deviceID}';

    final currentParticipants =
        room
            .getActiveMatrixRtcMembers()
            .map((member) => member.membershipId)
            .whereType<String>()
            .toSet()
          ..remove(ownMemberId);

    if (setEquals(currentParticipants, _lastSharedParticipants) &&
        currentParticipants.isNotEmpty) {
      Logs().d(
        'Participant list has not changed. No need to share keys again!',
      );
      return;
    }

    var index = encryption.keyProvider.getLatestIndex(
      ownMemberId,
    );

    final keyCreatedAt = _keyCreatedAt;
    final canJustForwardToNewUsers =
        keyCreatedAt != null &&
        DateTime.now().difference(keyCreatedAt).inSeconds < 15 &&
        _lastSharedParticipants.difference(currentParticipants).isEmpty;

    late final Uint8List key;
    if (_lastKey == null || !canJustForwardToNewUsers) {
      // Key generation
      final rng = Random.secure();
      key = Uint8List(16);
      key.setAll(0, Iterable.generate(key.length, (i) => rng.nextInt(256)));
      if (_lastKey != null) index = (index + 1) % 256;

      await encryption.keyProvider.setRawKey(
        key,
        keyIndex: index,
        participantId: ownMemberId,
      );
      _keyCreatedAt = DateTime.now();
      _lastKey = key;
      if (_lastKey != null) {
        await liveKitRoom.e2eeManager?.setKeyIndex(
          index,
          participantIdentity: ownMemberId,
        );
      }
    } else {
      key = _lastKey!;
    }

    final forwardParticipants = canJustForwardToNewUsers
        ? currentParticipants.difference(_lastSharedParticipants)
        : currentParticipants;
    final deviceKeys = <DeviceKeys>[];
    for (final membershipId in forwardParticipants) {
      final membershipParts = membershipId.split(':');
      final deviceId = membershipParts.removeLast();
      final userId = membershipParts.join(':');
      final keys = room.client.userDeviceKeys[userId]?.deviceKeys[deviceId];
      if (keys == null) {
        Logs().w('No device keys found for $membershipId');
        continue;
      }
      deviceKeys.add(keys);
    }

    _lastSharedParticipants = currentParticipants;
    await room.shareMatrixRtcCallKey(
      key: key,
      index: index,
      memberId: ownMemberId,
      deviceKeys: deviceKeys,
    );
  }

  Future<void> _init() async {
    _onCallEncryptionKeysSub = room.client.onCallEncryptionKeys.listen(
      _onCallEncryptionKeys,
    );

    await WakelockPlus.enable();
    await lk.LiveKitClient.initialize();

    // kHKDF matches the key derivation used by element-web's LiveKit JS SDK
    final keyProviderOptions = rtc.KeyProviderOptions(
      sharedKey: false,
      ratchetSalt: Uint8List.fromList('LKFrameEncryptionKey'.codeUnits),
      ratchetWindowSize: 0,
      discardFrameWhenCryptorNotReady: true,
      keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
      keyRingSize: 255,
    );

    // FrameCryptor 在 web 端依赖 e2ee.worker.dart.js（需随 web 构建部署）。
    // 若 worker 缺失或浏览器不支持 Insertable Streams，此处会抛异常；
    // 捕获后标记 E2EE 不可用，避免后续静默超时卡死在「连接中」。
    lk.E2EEOptions? encryption;
    try {
      final nativeKeyProvider = await rtc.frameCryptorFactory
          .createDefaultKeyProvider(keyProviderOptions);
      final baseKeyProvider = _keyProvider = lk.BaseKeyProvider(
        nativeKeyProvider,
        keyProviderOptions,
      );
      encryption = lk.E2EEOptions(keyProvider: baseKeyProvider);
    } catch (e, s) {
      Logs().e(
        'Failed to initialize call E2EE (FrameCryptor). '
        'On web this usually means e2ee.worker.dart.js is missing or the '
        'browser does not support Insertable Streams.',
        e,
        s,
      );
      _e2eeInitError = e;
    }

    final liveKitRoom = value.room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: _cameraCaptureOptions1v1,
        defaultVideoPublishOptions: _videoPublishOptions1v1,
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          highPassFilter: true,
        ),
        defaultScreenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          useiOSBroadcastExtension: PlatformInfos.isIOS,
        ),
        defaultAudioOutputOptions: lk.AudioOutputOptions(
          speakerOn: PlatformInfos.isMobile,
        ),
        encryption: encryption,
      ),
    );

    liveKitRoom.events.on<lk.ParticipantConnectedEvent>((event) async {
      if (event.participant.identity ==
          liveKitRoom.localParticipant?.identity) {
        return;
      }
      if (waitForOtherSide) {
        waitForOtherSide = false;
        await _audioPlayer.stop();
      }
      _playJoinSound();
    });

    liveKitRoom.events.on<lk.ParticipantDisconnectedEvent>(_playLeaveSound);

    // 远程静音请求：管理员通过数据通道发送 mute 指令
    liveKitRoom.events.on<lk.DataReceivedEvent>((event) {
      // 兼容旧版 LiveKit Server（不下发 topic）：topic 为空时也尝试解析
      if (event.topic != null && event.topic != 'mute') return;
      try {
        final payload =
            jsonDecode(utf8.decode(event.data)) as Map<String, Object?>;
        Logs().d(
          '[RemoteMute] received from ${event.participant?.identity}, topic: ${event.topic}, payload: $payload',
        );
        final muted = payload['muted'] as bool?;
        if (muted != null) {
          final local = liveKitRoom.localParticipant;
          local?.setMicrophoneEnabled(!muted);
        }
      } catch (e) {
        // 非 mute 消息（如其他数据）解析失败属正常，不打 warning
        Logs().v('Ignored non-JSON data packet (topic: ${event.topic})');
      }
    });

    liveKitRoom.events.on<lk.TrackE2EEStateEvent>((event) {
      if (event.state == .kOk || event.state == .kNew) {
        Logs().i(
          'E2EE event from ${event.participant} (${event.publication})',
          event.state,
        );
        return;
      }
      if (event.state == .kMissingKey) {
        Logs().d('Waiting for call key...', event);
        return;
      }
      if (event.state == .kDecryptionFailed) {
        Logs().w(
          'E2EE decryption failed from ${event.participant.identity} '
          '(publication ${event.publication.sid}) — likely a key index mismatch',
        );
        return;
      }
      Logs().e('LiveKit E2EE Error', event);
    });

    // [调试] 屏幕共享轨的发布/订阅/流状态事件，定位手机端看不到桌面
    liveKitRoom.events.on<lk.TrackPublishedEvent>((event) {
      if (event.publication.kind == lk.TrackType.VIDEO) {
        Logs().d(
          '[CallDebug] TrackPublished participant=${event.participant.identity} '
          'sid=${event.publication.sid} name=${event.publication.name} '
          'isScreenShare=${event.publication.isScreenShare}',
        );
      }
    });
    liveKitRoom.events.on<lk.TrackSubscribedEvent>((event) {
      if (event.publication.kind == lk.TrackType.VIDEO) {
        Logs().d(
          '[CallDebug] TrackSubscribed participant=${event.participant.identity} '
          'sid=${event.publication.sid} '
          'isScreenShare=${event.publication.isScreenShare} '
          'track=${event.track.sid}',
        );
      }
    });
    liveKitRoom.events.on<lk.TrackUnsubscribedEvent>((event) {
      if (event.publication.kind == lk.TrackType.VIDEO) {
        Logs().d(
          '[CallDebug] TrackUnsubscribed participant=${event.participant.identity} '
          'sid=${event.publication.sid} '
          'isScreenShare=${event.publication.isScreenShare}',
        );
      }
    });
    liveKitRoom.events.on<lk.TrackStreamStateUpdatedEvent>((event) {
      if (event.publication.kind == lk.TrackType.VIDEO) {
        Logs().d(
          '[CallDebug] TrackStreamState participant=${event.participant.identity} '
          'sid=${event.publication.sid} '
          'isScreenShare=${event.publication.isScreenShare} '
          'streamState=${event.streamState.name}',
        );
      }
    });

    liveKitRoom.addListener(notifyListeners);

    if (room.isDirectChat && room.hasActiveMatrixRtcCall) {
      await connect();
    } else {
      // 纯语音主叫：不创建摄像头轨道，避免呼叫前就申请相机权限，
      // connect() 会根据 localVideoTrack == null 推导出 voice 意图
      if (initialIntent != MatrixRtcCallIntent.voice) {
        value.localVideoTrack = await _createCameraTrack();
        if (room.getActiveMatrixRtcMembers().firstOrNull?.callIntent ==
            .voice) {
          value.localVideoTrack?.mute();
        }
        value.localVideoTrack?.addListener(notifyListeners);
      }
      notifyListeners();
      // 主叫：预览准备好后自动发起呼叫（纯语音直接发起）
      if (initialIntent != null) {
        await connect();
      }
    }
  }

  /// 创建本地麦克风轨道。
  ///
  /// 若设备无麦克风、被占用或浏览器拒绝权限，返回 null 并记录日志，
  /// 避免未捕获异常中断通话流程。
  Future<lk.LocalAudioTrack?> _createAudioTrack() async {
    try {
      final track = await lk.LocalAudioTrack.create();
      microphoneAvailable = true;
      return track;
    } catch (e, s) {
      Logs().w('Unable to acquire microphone', e, s);
      microphoneAvailable = false;
      return null;
    }
  }

  /// 创建本地摄像头轨道。
  ///
  /// 若设备无摄像头、被占用或浏览器拒绝权限，返回 null 并记录日志，
  /// 由调用方决定是否回退为语音通话，避免未捕获异常中断通话流程。
  Future<lk.LocalVideoTrack?> _createCameraTrack() async {
    try {
      final track = await lk.LocalVideoTrack.createCameraTrack(
        _cameraCaptureOptions1v1,
      );
      cameraAvailable = true;
      return track;
    } catch (e, s) {
      Logs().w('Unable to acquire camera, falling back to audio-only', e, s);
      cameraAvailable = false;
      return null;
    }
  }

  Future<void> togglePreviewCamera() async {
    final track = value.localVideoTrack;
    if (track == null) return;
    if (!track.muted) {
      await track.mute();
      return;
    }
    track.removeListener(notifyListeners);
    await track.stop();
    value.localVideoTrack = await _createCameraTrack();
    value.localVideoTrack?.addListener(notifyListeners);

    notifyListeners();
  }

  void togglePreviewMic() {
    value.startWithAudio = !value.startWithAudio;
    notifyListeners();
  }

  bool participantRaisedHand(String matrixId) {
    final timeline = this.timeline;
    if (timeline == null) return false;
    return room.participantRaisedHandInMatrixRtcCall(matrixId, timeline);
  }

  Future<void> _onNewTimelineEvent(int i) async {
    final event = timeline?.events[i];
    if (event == null) return;
    switch (event.type) {
      case 'io.element.call.reaction':
        Logs().d(
          'Call reactions are not yet handled',
          event.content.tryGet<String>('emoji'),
        );
        // TODO: handle reaction
        break;
      case EventTypes.Reaction:
        final reactedEvent = await timeline!.getEventById(
          event.relationshipEventId!,
        );
        if (reactedEvent != null &&
            reactedEvent.type == MatrixRtcCallMember.eventType &&
            event.senderId == reactedEvent.senderId &&
            event.content
                    .tryGetMap<String, Object?>('m.relates_to')
                    ?.tryGet<String>('key') ==
                '🖐️') {
          Logs().d('User raised hand!');
          _playRaiseHandSound();
          notifyListeners();
        }
        break;
      case EventTypes.Redaction:
        notifyListeners();
        break;
    }
  }

  Future<void> connect() async {
    if (_e2eeInitError != null) {
      Logs().w(
        'Call E2EE (FrameCryptor) failed to initialize; call will proceed '
        'without end-to-end encryption and may not connect to peers that '
        'require it. Cause: $_e2eeInitError',
      );
    }
    try {
      value.isLoading = true;
      notifyListeners();
      final playWaitingSound =
          !room.hasActiveMatrixRtcCall && room.isDirectChat;

      final intent =
          room.getActiveMatrixRtcMembers().firstOrNull?.callIntent ??
          (value.localVideoTrack?.muted == false ? .video : .voice);
      if (PlatformInfos.isMobile) {
        await lk.AudioManager.instance.setSpeakerOutputPreferred(
          intent == .video,
        );
      }

      // getTimeline 仅用于通话表情等非核心功能，大房间加载历史消息可能
      // 耗时数百毫秒甚至更久，放在连接 LiveKit 之前会阻塞入会。
      // 移到连接成功后异步加载，避免拖慢首帧。
      unawaited(
        room.getTimeline(onInsert: _onNewTimelineEvent).then((t) {
          timeline = t;
        }).catchError((e) {
          Logs().w('Unable to load call timeline', e);
        }),
      );

      Logs().d('[CallConnect] (1/4) joinMatrixRtcCall...');
      final joinResult = await room.joinMatrixRtcCall(intent: intent);
      ringEventId = joinResult.ringEventId;
      final credentials = joinResult.credentials;
      _onCallMembersChanged = room.client.onSync.stream
          .where(
            (syncUpdate) =>
                syncUpdate.rooms?.join?[room.id]?.timeline?.events?.any(
                  (event) => event.type == MatrixRtcCallMember.eventType,
                ) ??
                false,
          )
          .listen((_) {
            notifyListeners();
            _createKeyAndShare();
          });
      await _createKeyAndShare();

      final startWithAudio = value.startWithAudio;
      await value.localVideoTrack?.stop();
      await value.localVideoTrack?.dispose();
      value.localVideoTrack = null;
      _enableLiveKitDebugLogging();
      // 音视频轨道创建会触发安卓 RECORD_AUDIO/CAMERA 运行时权限申请，
      // 需在前台服务（microphone/camera 类型）启动前完成。
      // 麦克风不可用（无设备、被占用、权限被拒）时 audioTrack 为 null，
      // 通话以静音入会，避免 getUserMedia 异常中断整个 connect()。
      final audioTrack = startWithAudio
          ? await _createAudioTrack()
          : null;
      // 视频采集失败（无摄像头、被占用、权限被拒）时回退为语音通话，
      // 避免整个 connect() 被未捕获异常中断。
      var startWithVideo =
          !(value.localVideoTrack?.muted ?? intent == .voice);
      final videoTrack = startWithVideo
          ? await _createCameraTrack()
          : null;
      if (startWithVideo && videoTrack == null) {
        Logs().w('Camera unavailable, downgrading to audio-only call');
        startWithVideo = false;
      }
      // 麦克风和摄像头都不可用也不报错：仍然正常连接 SFU，以纯接收方式
      // 观看对方视频；下方控制按钮根据设备可用性显示禁用态。
      // 持有麦克风/摄像头类型的前台服务：
      // Android 14 后台采集要求，且可提升弱网/国产 ROM 下的
      // 网络（UDP）与进程优先级，降低 ICE 超时概率。
      await CallForegroundService.start(video: startWithVideo);
      Logs().d('[CallConnect] (2/4) connect to LiveKit SFU...');
      // 整体连接超时兜底：LiveKit 内部 ICE 超时 30s，加上 SFU 凭证获取
      // （已限 15s/次 x 3 重试），正常情况下 60s 内必定完成。超过 90s
      // 仍未连上视为失败，避免用户无限卡在「连接中」。
      await value.room!
          .connect(
            credentials.url,
            credentials.jwt,
            // 默认 ICE 连接超时仅 10s，移动网络走 TURN/TCP 回退时可能不够，
            // 放宽到 30s；预取 ICE 候选可加快弱网下的连通速度。
            connectOptions: lk.ConnectOptions(
              rtcConfiguration:
                  const lk.RTCConfiguration(iceCandidatePoolSize: 4),
              timeouts: const lk.Timeouts(
                connection: Duration(seconds: 30),
                debounce: Duration(milliseconds: 20),
                publish: Duration(seconds: 15),
                subscribe: Duration(seconds: 15),
                peerConnection: Duration(seconds: 30),
                iceRestart: Duration(seconds: 15),
              ),
            ),
            fastConnectOptions: lk.FastConnectOptions(
              microphone: lk.TrackOption(track: audioTrack),
              camera: lk.TrackOption(track: videoTrack),
            ),
          )
          .timeout(const Duration(seconds: 90));
      Logs().d('[CallConnect] (3/4) LiveKit connected.');
      _startVideoStatsDebug();

      _resendCallMemberState?.cancel();
      // 心跳：定时重发自己的 m.call.member 入会状态以续期。
      // 间隔需远短于 maxRtcMembershipAlive（60 秒），否则成员会被误判
      // 为过期而从通话人数/头像框中消失。
      _resendCallMemberState = Timer.periodic(const Duration(seconds: 40), (_) {
        final ownMembership = room.ownMatrixRtcMembership;
        if (ownMembership == null) {
          _resendCallMemberState?.cancel();
          return;
        }
        room.setMatrixRtcMembershipState(
          ownMembership.fociPreferred,
          intent: intent,
        );
      });
      startTime = DateTime.now();
      Logs().d('[CallConnect] (4/4) call established.');

      if (playWaitingSound) {
        waitForOtherSide = true;
        _playWaitingSound();
      } else {
        _playJoinSound();
      }

      notifyListeners();
    } catch (e, s) {
      Logs().e('Error while connecting', e, s);
      // 用户已主动挂断时，连接超时/中断属于预期行为，不再展示"呼叫失败"
      if (_disposed || _closing) {
        await CallForegroundService.stop();
        return;
      }
      value.error = e;
      ErrorReporter(null, 'Unable to connect').onErrorCallback(e, s);
      await CallForegroundService.stop();
    } finally {
      value.isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> close(BuildContext context) async {
    _closing = true;
    _statsDebugTimer?.cancel();
    _playLeaveSound();
    final liveKitRoom = value.room;
    if (liveKitRoom != null) {
      liveKitRoom.removeListener(notifyListeners);
      await showFutureLoadingDialog(
        context: context,
        future: () async {
          try {
            if (liveKitRoom.connectionState !=
                lk.ConnectionState.disconnected) {
              await liveKitRoom.disconnect();
            }
            await liveKitRoom.dispose();
          } catch (e) {
            // 挂断时连接尚未建立，disconnect/dispose 抛异常属正常，忽略
            Logs().w('Error while disconnecting livekit room', e);
          }
          value.room = null;
          if (room.ownMatrixRtcMembership != null) {
            await room.leaveMatrixRtcCall();
          }
        },
      );
    }
    await CallForegroundService.stop();
    if (context.mounted) {
      Matrix.of(context).activeCallRoomId.value = null;
    }
  }

  bool _disposed = false;
  /// 用户已主动挂断，连接过程中的异常不再展示
  bool _closing = false;

  static bool _liveKitLoggingEnabled = false;

  /// debug 模式下打开 LiveKit 详细日志（iceServers、ICE 状态、candidate 等），
  /// 便于排查 "Timed out waiting for PeerConnection to connect"。
  ///
  /// 任何日志相关异常都不得影响通话连接本身。
  void _enableLiveKitDebugLogging() {
    if (_liveKitLoggingEnabled || !kDebugMode) return;
    _liveKitLoggingEnabled = true;
    try {
      // livekit 的 logger 是具名 logger（Logger('livekit')），
      // package:logging 要求先开启层级日志，否则设置 level 会抛异常。
      logging.hierarchicalLoggingEnabled = true;
      lk.setLoggingLevel(lk.LoggerLevel.kFINE);
      lk.logger.onRecord.listen((record) {
        Logs().d('[LiveKit ${record.level.name}] ${record.message}');
        if (record.error != null) {
          Logs().w(
            '[LiveKit] ${record.message}',
            record.error,
            record.stackTrace,
          );
        }
      });
    } catch (e) {
      Logs().w('Unable to enable LiveKit debug logging', e);
    }
  }

  /// debug 模式下每 5 秒打印视频收发统计，用于定位画质瓶颈在哪一端：
  ///
  /// - `↑` 发送行：`limit:` 显示编码器受限原因（none/bandwidth/cpu/other），
  ///   分辨率或码率上不去 → 发送端问题（旧包未生效 / 相机采集回退 / CPU 降级）；
  /// - `↓` 接收行：发送端正常但接收分辨率/码率低 → SFU 只转发了低层，
  ///   通常是下行带宽估计不足（丢包/高延迟线路）或服务端配置限制，
  ///   不是 App 侧能解决的。
  void _startVideoStatsDebug() {
    if (!kDebugMode) return;
    _statsDebugTimer?.cancel();
    // 上一轮快照，用于计算码率增量；key 为 trackSid(+:rid)
    final prevSender = <String, num>{};
    final prevSenderTs = <String, num>{};
    final prevReceiver = <String, num>{};
    final prevReceiverTs = <String, num>{};
    final prevRecvLost = <String, num>{};
    final prevRecvPackets = <String, num>{};
    _statsDebugTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_disposed) return;
      final liveKitRoom = value.room;
      if (liveKitRoom == null ||
          liveKitRoom.connectionState != lk.ConnectionState.connected) {
        return;
      }
      try {
        final localPublications =
            liveKitRoom.localParticipant?.videoTrackPublications;
        if (localPublications != null) {
          for (final publication in localPublications) {
            if (publication.isScreenShare) continue;
            final track = publication.track;
            if (track == null) continue;
            for (final s in await track.getSenderStats()) {
              final key = '${track.sid}:${s.rid ?? ''}';
              final prevBytes = prevSender[key];
              final prevTs = prevSenderTs[key];
              prevSender[key] = s.bytesSent ?? 0;
              prevSenderTs[key] = s.timestamp;
              var kbps = 0;
              if (prevBytes != null && prevTs != null && s.timestamp > prevTs) {
                kbps =
                    (((s.bytesSent ?? 0) - prevBytes) *
                            8 /
                            (s.timestamp - prevTs))
                        .round();
              }
              Logs().d(
                '[CallStats] ↑ ${s.rid ?? 'video'} '
                '${s.frameWidth ?? '?'}x${s.frameHeight ?? '?'} '
                '${s.framesPerSecond ?? '?'}fps '
                '${(kbps / 1000).toStringAsFixed(2)}Mbps '
                'limit:${s.qualityLimitationReason ?? '?'}',
              );
            }
          }
        }
        for (final participant in liveKitRoom.remoteParticipants.values) {
          for (final publication in participant.videoTrackPublications) {
            if (publication.isScreenShare) continue;
            final track = publication.track;
            if (track == null) continue;
            final s = await track.getReceiverStats();
            if (s == null) continue;
            final key = track.sid ?? 'video';
            final prevBytes = prevReceiver[key];
            final prevTs = prevReceiverTs[key];
            prevReceiver[key] = s.bytesReceived ?? 0;
            prevReceiverTs[key] = s.timestamp;
            var kbps = 0;
            if (prevBytes != null && prevTs != null && s.timestamp > prevTs) {
              kbps =
                  (((s.bytesReceived ?? 0) - prevBytes) *
                          8 /
                          (s.timestamp - prevTs))
                      .round();
            }
            final lostDelta = (s.packetsLost ?? 0) - (prevRecvLost[key] ?? 0);
            final packetsDelta =
                (s.packetsReceived ?? 0) - (prevRecvPackets[key] ?? 0);
            prevRecvLost[key] = s.packetsLost ?? 0;
            prevRecvPackets[key] = s.packetsReceived ?? 0;
            final lostPct = packetsDelta > 0
                ? (lostDelta / packetsDelta * 100).toStringAsFixed(1)
                : '?';
            Logs().d(
              '[CallStats] ↓ ${participant.identity} '
              '${s.frameWidth ?? '?'}x${s.frameHeight ?? '?'} '
              '${s.framesPerSecond ?? '?'}fps '
              '${(kbps / 1000).toStringAsFixed(2)}Mbps '
              'lost:$lostPct% '
              'quality:${publication.videoQuality}',
            );
          }
        }
      } catch (e) {
        Logs().w('[CallStats] unable to collect stats', e);
      }
    });
  }

  /// 连接/断开有长达十几秒的异步过程，页面可能在其完成前被销毁。
  /// dispose 之后所有通知直接丢弃，避免
  /// "A ChangeNotifier was used after being disposed" 异常。
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _onCallEncryptionKeysSub?.cancel();
    _onCallMembersChanged?.cancel();
    _resendCallMemberState?.cancel();
    _statsDebugTimer?.cancel();
    timeline?.cancelSubscriptions();
    value.localVideoTrack?.dispose();
    CallForegroundService.stop();
    final liveKitRoom = value.room;
    if (liveKitRoom != null) {
      liveKitRoom.removeListener(notifyListeners);
      if (liveKitRoom.connectionState != lk.ConnectionState.disconnected) {
        liveKitRoom.disconnect();
      }
      liveKitRoom.dispose();
      room.leaveMatrixRtcCall();
    }
    _audioPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _playSoundIndex(
    AudioSource audioSource, {
    LoopMode loopMode = .off,
  }) async {
    if (_audioPlayer.playing) await _audioPlayer.stop();
    await _audioPlayer.setAudioSource(audioSource);
    if (_audioPlayer.loopMode != loopMode) {
      await _audioPlayer.setLoopMode(loopMode);
    }
    try {
      await _audioPlayer.play();
    } catch (e) {
      Logs().w('Unable to start audio player. Try again...', e);
      await Future.delayed(const Duration(milliseconds: 300));
      await _audioPlayer.play();
    }
  }

  final _joinSource = AudioSource.asset('assets/sounds/call_join.mp3');
  final _leaveSource = AudioSource.asset('assets/sounds/call_leave.mp3');
  final _raiseHandSource = AudioSource.asset(
    'assets/sounds/call_attention.mp3',
  );
  final _waitSource = AudioSource.asset('assets/sounds/call_wait.mp3');

  Future<void> _playJoinSound() => _playSoundIndex(_joinSource);

  Future<void> _playLeaveSound([_]) => _playSoundIndex(_leaveSource);

  Future<void> _playRaiseHandSound() => _playSoundIndex(_raiseHandSource);

  Future<void> _playWaitingSound() =>
      _playSoundIndex(_waitSource, loopMode: .all);

  Future<lk.MediaDevice?> _selectMediaDevice(
    BuildContext context,
    List<lk.MediaDevice> devices,
    String? activeDeviceId,
  ) async {
    if (!context.mounted) return null;
    return await showMenu<lk.MediaDevice>(
      context: context,
      position: context.position,
      items: devices.isEmpty
          ? [
              PopupMenuItem(
                enabled: false,
                child: Text(L10n.of(context).noDevicesFound),
              ),
            ]
          : devices
                .map(
                  (device) => PopupMenuItem(
                    value: device,
                    child: Row(
                      mainAxisSize: .min,
                      spacing: 12,
                      children: [
                        Icon(
                          device.deviceId == activeDeviceId
                              ? Icons.check_circle_outlined
                              : Icons.circle_outlined,
                        ),
                        Expanded(
                          child: Text(
                            device.label,
                            maxLines: 1,
                            overflow: .ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
    );
  }

  Future<void> selectCamera(BuildContext context) async {
    final devices = await lk.Hardware.instance.videoInputs();
    if (!context.mounted) return;
    final source = await _selectMediaDevice(
      context,
      devices,
      value.room?.selectedVideoInputDeviceId,
    );
    if (source == null) return;
    await value.room?.setVideoInputDevice(source);
  }

  Future<void> selectMicrophone(BuildContext context) async {
    final devices = await lk.Hardware.instance.audioInputs();
    if (!context.mounted) return;
    final source = await _selectMediaDevice(
      context,
      devices,
      value.room?.selectedAudioInputDeviceId,
    );
    if (source == null) return;
    await value.room?.setAudioInputDevice(source);
  }

  Future<void> selectSpeaker(BuildContext context) async {
    final devices = await lk.Hardware.instance.audioOutputs();
    if (!context.mounted) return;
    if (devices.isEmpty && PlatformInfos.isMobile) {
      final preferSpeaker = lk.AudioManager.instance.isSpeakerOutputPreferred;
      final toggle = await showMenu<bool>(
        context: context,
        position: context.position,
        items: [
          PopupMenuItem(
            value: true,
            child: Row(
              mainAxisSize: .min,
              spacing: 12,
              children: [
                Icon(
                  preferSpeaker
                      ? Icons.check_circle_outlined
                      : Icons.circle_outlined,
                ),
                Expanded(
                  child: Text(
                    L10n.of(context).preferSpeaker,
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      if (toggle == null) return;
      await lk.AudioManager.instance.setSpeakerOutputPreferred(!preferSpeaker);
      return;
    }
    final source = await _selectMediaDevice(
      context,
      devices,
      value.room?.selectedAudioOutputDeviceId,
    );
    if (source == null) return;
    await value.room?.setAudioOutputDevice(source);
  }
}
