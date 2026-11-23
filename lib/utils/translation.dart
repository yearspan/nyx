import 'dart:convert';

import 'package:http/http.dart' as http;

/// 轻量翻译工具：基于字符集判断文本与当前 locale 是否同语言，
/// 并调用免费翻译接口把文本翻译成目标语言。
class TranslationUtil {
  /// 判断 [text] 的主字符集是否与 [localeLanguageCode] 不同。
  /// 仅用于决定是否在长按菜单里展示「翻译」入口。
  static bool isDifferentLanguage(String text, String localeLanguageCode) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;

    final userIsCjk = _isCjkLocale(localeLanguageCode);
    final textHasCjk = _containsCjk(cleaned);
    // 中日韩用户收到非中日韩文本，或非中日韩用户收到中日韩文本，
    // 都认为是不同语言
    if (userIsCjk != textHasCjk) return true;

    // 同为拉丁字符系时，用简单的常见词/字符分布判断不同语种过于复杂，
    // 这里保守处理：拉丁系用户收到含西里尔/阿拉伯/天城文等非拉丁脚本时
    // 也视为不同语言
    if (!userIsCjk && !textHasCjk) {
      final hasNonLatin = _containsNonLatinScript(cleaned);
      if (hasNonLatin) return true;
    }
    return false;
  }

  static bool _isCjkLocale(String code) {
    final c = code.toLowerCase();
    return c.startsWith('zh') ||
        c.startsWith('ja') ||
        c.startsWith('ko') ||
        c == 'zh' ||
        c == 'ja' ||
        c == 'ko';
  }

  static bool _containsCjk(String text) {
    return text.contains(RegExp(
      r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]',
    ));
  }

  static bool _containsNonLatinScript(String text) {
    // 西里尔 / 阿拉伯 / 天城文 / 希伯来 / 泰文 等
    return text.contains(RegExp(
      r'[\u0400-\u04ff\u0590-\u05ff\u0600-\u06ff\u0900-\u097f\u0e00-\u0e7f]',
    ));
  }

  /// 把 [text] 翻译成 [targetLanguageCode]（如 'zh'、'en'）。
  /// 失败时返回 null。
  static Future<String?> translate(
    String text, {
    required String targetLanguageCode,
  }) async {
    final source = text.trim();
    if (source.isEmpty) return null;

    // MyMemory 免费翻译接口（国内可访问，无需 key，每日有免费额度）
    try {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {
        'q': source,
        'langpair': 'Autodetect|$targetLanguageCode',
      });
      final resp = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final translated =
          data['responseData']?['translatedText']?.toString();
      if (translated == null || translated.isEmpty) return null;
      return translated.trim();
    } catch (_) {
      return null;
    }
  }
}
