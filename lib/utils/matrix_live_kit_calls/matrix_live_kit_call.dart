import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/call_keys_event_content.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:matrix/matrix.dart';

/// 当前用户无权在房间内发起/加入 MatrixRTC 通话（m.call.member 状态
/// 事件的发送级别高于用户权力级，且用户也无法修改 power levels）。
class MatrixRtcCallPermissionException implements Exception {
  @override
  String toString() =>
      'No permission to join the MatrixRTC call in this room';
}

extension MatrixRtcClientExtension on Client {
  Future<List<String>> getLiveKitServiceUrls() async {
    final wellKnown = await getWellknown();
    final rtcFociMap = wellKnown.additionalProperties
        .tryGetMap<String, Object?>(
          'org.matrix.msc4143.rtc_foci',
          TryGet.silent,
        ); // Famedly style
    if (rtcFociMap != null) {
      return [?rtcFociMap.tryGet<String>('livekit_service_url')];
    }

    // TODO: Also query /_matrix/client/unstable/org.matrix.msc4143/rtc/transports

    return wellKnown.additionalProperties
            .tryGetList<Map<String, Object?>>('org.matrix.msc4143.rtc_foci')
            ?.map((foci) => foci.tryGet<String>('livekit_service_url'))
            .whereType<String>()
            .toList() ??
        [
          if (AppSettings.fallbackLiveKitInstance.value.isNotEmpty)
            AppSettings.fallbackLiveKitInstance.value,
        ];
  }

  Stream<CallKeysEvent> get onCallEncryptionKeys => onToDeviceEvent.stream
      .where((event) => event.type == CallKeysEventContent.eventType)
      .map(CallKeysEvent.fromToDeviceEvent);
}

extension MatrixRtcRoomExtension on Room {
  bool get hasActiveMatrixRtcCall => getActiveMatrixRtcMembers().isNotEmpty;

  MatrixRtcCallIntent? get activeMatrixRtcCallIntent {
    final members = getActiveMatrixRtcMembers();
    if (members.isEmpty) return null;
    if (members.any((member) => member.callIntent == .video)) return .video;
    return .voice;
  }

  bool get hasPermissionForMatrixRtcCall =>
      canChangeStateEvent(MatrixRtcCallMember.eventType);

  /// 被叫方拒绝接听时，向主叫方发送一条未加密的
  /// `org.matrix.msc4075.rtc.notification` 事件并携带
  /// `m.call.reject: true` 自定义字段。
  ///
  /// MatrixRTC 规范没有定义"拒绝"事件，主叫方在通话页监听该事件后立即
  /// 结束呼叫，避免一直停留在"呼叫中"。移动端全屏来电页与桌面/Web 来电
  /// 弹窗共用此逻辑。使用 client.sendMessage 直接发送未加密事件，避免
  /// 加密/解密带来的延迟。
  Future<void> sendCallRejectNotification() async {
    final dmUserId = directChatMatrixID;
    final content = {
      ...RtcNotificationContent.create(
        type: RtcNotificationType.notification,
      ).toJson(),
      // 自定义字段：表示被叫方拒绝接听
      'm.call.reject': true,
      'm.mentions': {
        if (dmUserId != null) 'user_ids': [dmUserId],
      },
    };
    final txnId = client.generateUniqueTransactionId();
    await client.sendMessage(
      id,
      RtcNotificationContent.eventType,
      txnId,
      content,
    );
  }

  /// 确保本房间允许普通成员写入自己的 m.call.member 入会状态。
  ///
  /// 新建的群聊在创建时已把该事件级别设为 0，但已有的私聊或由其他客户端
  /// （如 Element）创建的群可能沿用 state_default=50，导致入会 403。
  /// 只要我能编辑 m.room.power_levels（房主/管理员），就把该事件开放为
  /// 0 级。返回当前用户是否真的具备写入 m.call.member 的权限：
  /// 管理员已自动开放或原本就是 0 级时为 true；普通成员在未开放的老
  /// 房间中为 false（服务端一定会返回 M_FORBIDDEN，无需再尝试）。
  Future<bool> ensureMatrixRtcCallPermission() async {
    final current =
        getState(EventTypes.RoomPowerLevels)?.content ??
        <String, Object?>{};
    final events = Map<String, Object?>.from(
      (current['events'] as Map?)?.cast<String, Object?>() ??
          <String, Object?>{},
    );
    // 已是 0（任何人可写），无需处理
    if ((events[MatrixRtcCallMember.eventType] as num?) == 0) {
      return true;
    }
    // 能改 power levels（房主/管理员）时自动开放；
    if (canChangeStateEvent(EventTypes.RoomPowerLevels)) {
      events[MatrixRtcCallMember.eventType] = 0;
      final updated = Map<String, Object?>.from(current)..['events'] = events;
      await client.setRoomStateWithKey(
        id,
        EventTypes.RoomPowerLevels,
        '',
        updated,
      );
      return true;
    }
    // 普通成员且房间未开放：服务端必然拒绝，直接告知调用方。
    return false;
  }

  List<MatrixRtcCallMember> getActiveMatrixRtcMembers() {
    final states = this.states[MatrixRtcCallMember.eventType];
    if (states == null) return [];
    // Empty content {} means the member has left — filter those out
    final activeMemberStates = states.values.where((event) {
      if (event.content.isEmpty) return false;
      if (event is! Event) return false;
      try {
        final validContent = MatrixRtcCallMember.fromJson(
          event.content,
          senderId: event.senderId,
        );
        if (validContent.focusActive?.type != 'livekit') return false;
        if (!isMatrixRtcMembershipAlive(validContent, event.originServerTs)) {
          return false;
        }
        return true;
      } catch (e, s) {
        Logs().d('Invalid "org.matrix.msc3401.call.member" event!', e, s);
        return false;
      }
    });
    return activeMemberStates
        .map(
          (state) => MatrixRtcCallMember.fromJson(
            state.content,
            senderId: state.senderId,
          ),
        )
        .toList();
  }

  /// 判定一条 RTC 入会状态是否仍然存活。
  ///
  /// 正常心跳会不断续期；但当用户把 App 直接滑掉（进程被杀）时，
  /// 来不及把状态改成空 content，只能靠「创建时间 + 过期时长」让其
  /// 自然失效。协议默认 expires 是小时级，那在 UI 上会表现为退出者
  /// 的头像/人数长时间残留，因此这里额外设置一个较短的存活上限。
  static const Duration maxRtcMembershipAlive = Duration(seconds: 60);

  bool isMatrixRtcMembershipAlive(
    MatrixRtcCallMember member,
    DateTime eventTs,
  ) {
    final now = DateTime.now();
    final createdAt = member.createdAt ?? eventTs;
    final protocolExpiry = createdAt.add(member.expires);
    // 以协议过期时间与本地存活上限中较早者为准。
    final effectiveLifetime = member.expires > maxRtcMembershipAlive
        ? maxRtcMembershipAlive
        : member.expires;
    final effectiveExpiry = createdAt.add(effectiveLifetime);
    return effectiveExpiry.isAfter(now) && protocolExpiry.isAfter(now);
  }

  /// 下一条当前活跃成员状态变为过期的时间点；无活跃成员返回 null。
  /// UI 可据此安排一次重建，让退出者的头像/人数准点消失。
  DateTime? nextMatrixRtcMembershipExpiry() {
    final states = this.states[MatrixRtcCallMember.eventType];
    if (states == null) return null;
    DateTime? next;
    for (final event in states.values) {
      if (event.content.isEmpty || event is! Event) continue;
      try {
        final member = MatrixRtcCallMember.fromJson(
          event.content,
          senderId: event.senderId,
        );
        if (member.focusActive?.type != 'livekit') continue;
        final createdAt = member.createdAt ?? event.originServerTs;
        final effectiveLifetime = member.expires > maxRtcMembershipAlive
            ? maxRtcMembershipAlive
            : member.expires;
        final expiry = createdAt.add(effectiveLifetime);
        if (expiry.isBefore(DateTime.now())) continue;
        if (next == null || expiry.isBefore(next)) next = expiry;
      } catch (_) {
        // ignore invalid member events
      }
    }
    return next;
  }

  String get _ownMatrixRtcMembershipStateKey =>
      '_${client.userID}_${client.deviceID}_m.call';

  MatrixRtcCallMember? get ownMatrixRtcMembership {
    final state = getState(
      MatrixRtcCallMember.eventType,
      _ownMatrixRtcMembershipStateKey,
    );
    if (state == null || state.content.isEmpty) return null;
    try {
      return MatrixRtcCallMember.fromJson(
        state.content,
        senderId: state.senderId,
      );
    } catch (e, s) {
      Logs().d(
        'Unknown format for ${MatrixRtcCallMember.eventType} event',
        e,
        s,
      );
      return null;
    }
  }

  Future<void> setMatrixRtcMembershipState(
    List<MatrixRtcFocusPreferred> fociPreferred, {
    MatrixRtcCallIntent intent = MatrixRtcCallIntent.video,
  }) => client.setRoomStateWithKey(
    id,
    MatrixRtcCallMember.eventType,
    _ownMatrixRtcMembershipStateKey,
    MatrixRtcCallMember(
      application: 'm.call',
      callId: '',
      deviceId: client.deviceID,
      expires: Duration(hours: 4),
      createdAt: DateTime.now(),
      fociPreferred: fociPreferred,
      focusActive: MatrixRtcFocusActive(
        focusSelection: 'oldest_membership',
        type: 'livekit',
      ),
      callIntent: intent,
      membershipId: '${client.userID}:${client.deviceID}',
      scope: 'm.room',
      senderId: null,
    ).toJson(),
  );

  bool participantRaisedHandInMatrixRtcCall(
    String matrixId,
    Timeline timeline,
  ) {
    final stateEvent =
        states[MatrixRtcCallMember.eventType]?[_ownMatrixRtcMembershipStateKey]
            as Event?;
    if (stateEvent == null) return false;
    final aggregatedEvents = timeline
        .aggregatedEvents[stateEvent.eventId]?['m.annotation']
        ?.where(
          (event) =>
              event.senderId == matrixId &&
              event.content
                      .tryGetMap<String, Object?>('m.relates_to')
                      ?.tryGet<String>('key') ==
                  '🖐️',
        );
    if (aggregatedEvents == null || aggregatedEvents.isEmpty) return false;

    return true;
  }

  Future<String?> raiseHandInMatrixRtcCall() async {
    final ownMemberStateEvent =
        states[MatrixRtcCallMember.eventType]?[_ownMatrixRtcMembershipStateKey]
            as Event?;
    if (ownMemberStateEvent == null) return null;
    return await sendReaction(ownMemberStateEvent.eventId, '🖐️');
  }

  Future<String?> lowerHandInMatrixRtcCall(Timeline timeline) async {
    final ownMemberStateEvent =
        states[MatrixRtcCallMember.eventType]?[_ownMatrixRtcMembershipStateKey]
            as Event?;
    if (ownMemberStateEvent == null) return null;
    final reaction = timeline.events.firstWhereOrNull(
      (event) =>
          event.type == EventTypes.Reaction &&
          event.relationshipEventId == ownMemberStateEvent.eventId &&
          event.senderId == client.userID &&
          event.status.isSent &&
          event.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key') ==
              '🖐️',
    );
    if (reaction == null) {
      throw Exception('Hand raise reaction event not found!');
    }
    return await reaction.redactEvent();
  }

  Future<void> shareMatrixRtcCallKey({
    required Uint8List key,
    required int index,
    required String memberId,
    required List<DeviceKeys> deviceKeys,
  }) async {
    if (deviceKeys.isEmpty) {
      Logs().d('No devices to share call keys with');
      return;
    }
    Logs().d(
      'Share call keys with',
      deviceKeys.map((key) => '${key.userId}:${key.deviceId}'),
    );

    final doNotEncryptTo = deviceKeys.where((d) => !d.encryptToDevice);
    if (doNotEncryptTo.isNotEmpty) {
      Logs().w(
        'Not sharing keys with ${doNotEncryptTo.length} device(s) because of key sharing restrictions!',
      );
      deviceKeys.removeWhere((d) => !d.encryptToDevice);
    }

    await client.sendToDeviceEncrypted(
      deviceKeys,
      CallKeysEventContent.eventType,
      CallKeysEventContent(
        keys: CallKeysEntry(index: index, key: base64Encode(key)),
        member: CallKeysMember(id: memberId, claimedDeviceId: client.deviceID!),
        roomId: id,
        sentTs: DateTime.now().millisecondsSinceEpoch,
        session: CallKeysSession(
          application: 'm.call',
          callId: '',
          scope: 'm.room',
        ),
      ).toJson(),
    );
  }

  Future<MatrixRtcJoinResult> joinMatrixRtcCall({
    MatrixRtcCallIntent intent = MatrixRtcCallIntent.video,
    List<String>? urls,
  }) async {
    await postLoad();
    // 老房间可能没开放 m.call.member 的写入权限：能改 power levels 时
    // 自动开放（设为 0 级）；普通成员在未开放的老房间中直接失败，
    // 不必发一次注定 403 的请求。
    if (!await ensureMatrixRtcCallPermission()) {
      throw MatrixRtcCallPermissionException();
    }
    if (ownMatrixRtcMembership != null) {
      Logs().w(
        'User has already an active rtc membership state in this room. Resetting it now...',
      );
      // 上次挂断没清干净（进程被杀 / 弱网丢包），先写空 content 清掉旧状态，
      // 否则自己在人数里会被算两次。
      try {
        await leaveMatrixRtcCall();
      } catch (e) {
        Logs().w('[MatrixRtc] Failed to reset stale membership', e);
      }
    }
    Logs().d('[Join MatrixRtc Call] (1/5) Get LiveKit Backend Urls...');

    final hasActiveMatrixRtcCall = this.hasActiveMatrixRtcCall;

    urls ??= getActiveMatrixRtcMembers()
        .map(
          (state) =>
              state.fociPreferred.map((focus) => focus.livekitServiceUrl),
        )
        .fold<List<String>>([], (urls, foci) => [...urls, ...foci]);

    if (urls.isEmpty) {
      urls.addAll(await client.getLiveKitServiceUrls());
    }

    Logs().v('Available SFUs', urls);
    if (urls.isEmpty) {
      throw Exception('This server does not support livekit calls!');
    }

    Logs().d(
      '[Join MatrixRtc Call] (2/5) Set "${MatrixRtcCallMember.eventType}" State event...',
    );
    await setMatrixRtcMembershipState(
      urls
          .map(
            (url) => MatrixRtcFocusPreferred(
              type: 'livekit',
              livekitServiceUrl: url,
              livekitAlias: id,
            ),
          )
          .toList(),
      intent: intent,
    );

    String? ringEventId;
    if (!hasActiveMatrixRtcCall) {
      final dmUserId = directChatMatrixID;
      // 主叫振铃事件：带上通话意图，供对端推送/通话记录展示使用
      // （等价于 SDK 的 sendRtcNotification，额外写入 m.call.intent）
      //
      // 注意：来电事件不加密。MatrixRTC 规范建议来电通知事件不加密，
      // 原因是：1) 来电需在通话建立前快速到达，加密/解密（特别是等待
      // 密钥）会引入明显延迟，导致对方弹窗慢甚至漏弹；2) 来电事件本身
      // 不含通话内容，仅包含呼叫意图和 @ 提醒，无敏感信息。
      // room.sendEvent 会自动加密，这里改用 client.sendMessage 直接
      // 发送未加密事件。
      final content = {
        ...RtcNotificationContent.create(
          type: dmUserId != null
              ? RtcNotificationType.ring
              : RtcNotificationType.notification,
        ).toJson(),
        'm.call.intent': intent.name,
        'm.mentions': {
          if (dmUserId != null) 'user_ids': [dmUserId],
          if (dmUserId == null) 'room': true,
        },
      };
      final txnId = client.generateUniqueTransactionId();
      ringEventId = await client.sendMessage(
        id,
        RtcNotificationContent.eventType,
        txnId,
        content,
      );
    }

    Logs().v('[Join MatrixRtc Call] (3/5) Request OpenId Token...');
    final openIdCredentials = await client.requestOpenIdToken(
      client.userID!,
      {},
    );

    for (final url in urls) {
      // 每个 SFU URL 最多重试 3 次：安卓弱网下 TLS 握手偶发中断，
      // 单次失败不应直接放弃该 SFU。
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          Logs().d(
            '[Join MatrixRtc Call] (4/5) Try authenticate to LiveKit instance $url (attempt ${attempt + 1})...',
          );
          // 向 SFU 申请 JWT 凭证必须有超时：弱网/国产移动网络下 TCP 连接
          // 可能挂起，Dart HttpClient 默认无超时（0），会让用户无限卡在
          // 「连接中」。单次请求限 15 秒，配合 3 次重试最多 45 秒。
          final response = await client.httpClient
              .post(
                Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/sfu/get'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'room': id,
                  'openid_token': openIdCredentials.toJson(),
                  'device_id': client.deviceID,
                }),
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) {
            throw Exception(response.reasonPhrase ?? response.body);
          }
          final json =
              jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
          Logs().d('Use SFU', url);
          return MatrixRtcJoinResult(
            credentials: MatrixRtcCredentials.fromJson(json),
            ringEventId: ringEventId,
          );
        } catch (e) {
          Logs().v(
            '[Join MatrixRtc Call] (4/4) Unable to authenticate to $url (attempt ${attempt + 1})',
            e,
          );
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          }
        }
      }
    }
    throw Exception(
      'Unable to authenticate to any of the visible LiveKit instances!\nSFU list: $urls\nActive Call: $hasActiveMatrixRtcCall',
    );
  }

  Future<void> leaveMatrixRtcCall() async {
    // 入会状态从没写成功过（如权限不足导致 join 失败）时，
    // 再发空 content 只会换来一次无意义的 403
    if (ownMatrixRtcMembership == null) return;
    // 挂断 / 进程回收时写空 content 可能因弱网失败，导致「通话结束后
    // 人数仍多一位」。这里最多重试 3 次，间隔递增，尽量把自己清掉。
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await client.setRoomStateWithKey(
          id,
          MatrixRtcCallMember.eventType,
          _ownMatrixRtcMembershipStateKey,
          {},
        );
        return;
      } catch (e) {
        Logs().w(
          '[MatrixRtc] leave failed attempt ${attempt + 1}',
          e,
        );
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
  }
}

class MatrixRtcCredentials {
  final String url, jwt;
  const MatrixRtcCredentials({required this.url, required this.jwt});
  factory MatrixRtcCredentials.fromJson(Map<String, Object?> json) =>
      MatrixRtcCredentials(
        url: json['url'] as String,
        jwt: json['jwt'] as String,
      );
}

/// 加入 MatrixRTC 通话的结果：LiveKit 凭证 + 主叫发出的振铃事件 ID
class MatrixRtcJoinResult {
  final MatrixRtcCredentials credentials;
  final String? ringEventId;

  const MatrixRtcJoinResult({
    required this.credentials,
    required this.ringEventId,
  });
}

enum MatrixRtcCallIntent {
  voice(callKitType: 0),
  video(callKitType: 1);

  final int callKitType;
  const MatrixRtcCallIntent({required this.callKitType});
}
