import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// 一通通话的结果（本设备视角）
enum CallRecordOutcome {
  /// 已接通（主叫被叫均用）
  answered,

  /// 来电未接
  missed,

  /// 主叫取消（未接通即挂断/呼叫失败）
  cancelled,
}

/// 一条通话记录，以振铃事件 ID（org.matrix.msc4075.rtc.notification）为键。
///
/// MatrixRTC 的通话结果/时长不写入房间历史（member state 会被离开时清空），
/// 因此在本设备通话结束时把结果持久化到本地，时间线里的振铃事件据此渲染
/// 为「拨出 / 来电 / 未接 / 已取消 + 时长」气泡。两台设备各自记录各自视角。
@immutable
class CallRecord {
  final CallRecordOutcome outcome;
  final Duration duration;
  final bool isVideo;

  /// 记录时间（用于清理旧数据）
  final DateTime savedAt;

  const CallRecord({
    required this.outcome,
    required this.duration,
    required this.isVideo,
    required this.savedAt,
  });

  Map<String, Object?> toJson() => {
    'o': outcome.name,
    'd': duration.inMilliseconds,
    'v': isVideo,
    't': savedAt.millisecondsSinceEpoch,
  };

  factory CallRecord.fromJson(Map<String, Object?> json) => CallRecord(
    outcome: CallRecordOutcome.values.firstWhere(
      (o) => o.name == json['o'],
      orElse: () => CallRecordOutcome.cancelled,
    ),
    duration: Duration(milliseconds: json.tryGet<int>('d') ?? 0),
    isVideo: json.tryGet<bool>('v') ?? false,
    savedAt: DateTime.fromMillisecondsSinceEpoch(
      json.tryGet<int>('t') ?? 0,
    ),
  );
}

/// 全局单例，[init] 后同步可读；保存后通知监听者刷新气泡
class CallRecordStore extends ChangeNotifier {
  CallRecordStore._();
  static final CallRecordStore instance = CallRecordStore._();

  static const _prefsKey = 'v2_call_records';
  static const _maxRecords = 300;

  final Map<String, CallRecord> _records = {};

  Future<void> init() async {
    try {
      final raw = AppSettings.store.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, Object?>;
      _records.clear();
      map.forEach((key, value) {
        if (value is Map<String, Object?>) {
          _records[key] = CallRecord.fromJson(value);
        }
      });
    } catch (e, s) {
      Logs().w('Unable to load call records', e, s);
    }
  }

  CallRecord? get(String ringEventId) => _records[ringEventId];

  Future<void> save({
    required String ringEventId,
    required CallRecordOutcome outcome,
    required Duration duration,
    required bool isVideo,
  }) async {
    _records[ringEventId] = CallRecord(
      outcome: outcome,
      duration: duration,
      isVideo: isVideo,
      savedAt: DateTime.now(),
    );
    // 简单清理：超出上限时删除最旧的
    if (_records.length > _maxRecords) {
      final sorted = _records.entries.toList()
        ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
      for (final entry in sorted.take(_records.length - _maxRecords)) {
        _records.remove(entry.key);
      }
    }
    notifyListeners();
    try {
      await AppSettings.store.setString(
        _prefsKey,
        jsonEncode(
          _records.map((key, value) => MapEntry(key, value.toJson())),
        ),
      );
    } catch (e, s) {
      Logs().w('Unable to persist call records', e, s);
    }
  }
}
