import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地翻译结果存储：eventId -> 翻译文本。
/// 持久化到 SharedPreferences，历史消息重新打开时仍可显示译文。
/// 通过 [translatedEventIds] 的 ValueNotifier 通知监听者刷新。
class TranslationStore {
  TranslationStore._();
  static final TranslationStore instance = TranslationStore._();

  static const String _prefsKey = 'v2_translations';

  /// eventId -> 翻译文本
  final Map<String, String> _translations = {};

  /// 已翻译的 eventId 集合，监听它来刷新界面
  final ValueNotifier<Set<String>> translatedEventIds = ValueNotifier(
    <String>{},
  );

  bool _loaded = false;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 从 SharedPreferences 加载（首次访问时自动加载）
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _translations.addAll(map.map((k, v) => MapEntry(k, v.toString())));
        translatedEventIds.value = _translations.keys.toSet();
      } catch (_) {}
    }
    _loaded = true;
  }

  /// 获取某事件的翻译文本，未翻译返回 null
  Future<String?> get(String eventId) async {
    await _ensureLoaded();
    return _translations[eventId];
  }

  /// 同步获取（用于已加载场景的快速读取）
  String? getSync(String eventId) => _translations[eventId];

  /// 保存翻译结果并通知刷新
  Future<void> set(String eventId, String text) async {
    await _ensureLoaded();
    if (text.trim().isEmpty) {
      _translations.remove(eventId);
    } else {
      _translations[eventId] = text.trim();
    }
    await _persist();
    final set = {...translatedEventIds.value};
    if (text.trim().isEmpty) {
      set.remove(eventId);
    } else {
      set.add(eventId);
    }
    translatedEventIds.value = set;
  }

  /// 清除某事件的翻译
  Future<void> remove(String eventId) async {
    await _ensureLoaded();
    if (_translations.remove(eventId) != null) {
      await _persist();
      final set = {...translatedEventIds.value};
      set.remove(eventId);
      translatedEventIds.value = set;
    }
  }

  Future<void> _persist() async {
    final prefs = await _ensurePrefs();
    await prefs.setString(_prefsKey, jsonEncode(_translations));
  }
}
