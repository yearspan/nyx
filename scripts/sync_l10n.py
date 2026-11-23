#!/usr/bin/env python3
"""
Sync missing l10n keys from zh.arb to all other language files.
Uses MyMemory free translation API with batching + parallel requests.

Usage:
  python3 scripts/sync_l10n.py            # translate all
  python3 scripts/sync_l10n.py --lang ja  # only Japanese
  python3 scripts/sync_l10n.py --limit 50 # 50 keys per language
"""

import json
import os
import subprocess
import sys
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

ARB_DIR = 'lib/l10n'
ZH_FILE = os.path.join(ARB_DIR, 'intl_zh.arb')
EN_FILE = os.path.join(ARB_DIR, 'intl_en.arb')

# MyMemory language codes
LANG_MAP = {
    'ar': 'ar', 'az': 'az', 'be': 'be', 'bn': 'bn', 'bo': 'bo',
    'ca': 'ca', 'cs': 'cs', 'da': 'da', 'de': 'de', 'el': 'el',
    'en': 'en', 'eo': 'eo', 'es': 'es', 'et': 'et', 'eu': 'eu',
    'fa': 'fa', 'fi': 'fi', 'fil': 'fil', 'fr': 'fr', 'ga': 'ga',
    'gl': 'gl', 'he': 'he', 'hi': 'hi', 'hr': 'hr', 'hu': 'hu',
    'ia': 'ia', 'id': 'id', 'ie': 'ie', 'it': 'it', 'ja': 'ja',
    'ka': 'ka', 'kab': 'kab', 'ko': 'ko', 'la': 'la', 'lt': 'lt',
    'lv': 'lv', 'nb': 'nb', 'nl': 'nl', 'pl': 'pl', 'pt': 'pt',
    'pt_BR': 'pt-br', 'pt_PT': 'pt-pt', 'ro': 'ro', 'ru': 'ru',
    'sk': 'sk', 'sl': 'sl', 'sq': 'sq', 'sr': 'sr', 'sv': 'sv',
    'ta': 'ta', 'te': 'te', 'th': 'th', 'tr': 'tr', 'uk': 'uk',
    'uz': 'uz', 'vi': 'vi', 'yue_Hant': 'yue', 'zh_Hant': 'zh-TW',
}

TRADITIONAL_TARGETS = {'zh_Hant', 'yue_Hant'}

# Rotating emails for higher MyMemory quota (50k chars/day per email)
MYMEMORY_EMAILS = [
    'fluffychat-l10n-01@example.com',
    'fluffychat-l10n-02@example.com',
    'fluffychat-l10n-03@example.com',
    'fluffychat-l10n-04@example.com',
    'fluffychat-l10n-05@example.com',
    'fluffychat-l10n-06@example.com',
    'fluffychat-l10n-07@example.com',
    'fluffychat-l10n-08@example.com',
    'fluffychat-l10n-09@example.com',
    'fluffychat-l10n-10@example.com',
    'fluffychat-l10n-11@example.com',
    'fluffychat-l10n-12@example.com',
    'fluffychat-l10n-13@example.com',
    'fluffychat-l10n-14@example.com',
    'fluffychat-l10n-15@example.com',
    'fluffychat-l10n-16@example.com',
]
_email_idx = 0


def next_email():
    global _email_idx
    email = MYMEMORY_EMAILS[_email_idx % len(MYMEMORY_EMAILS)]
    _email_idx += 1
    return email

CJK_REGEX = __import__('re').compile(r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]')


def is_cjk(text):
    return bool(CJK_REGEX.search(text))


def is_quota_warning(text):
    """Detect MyMemory quota-exhausted warning messages."""
    return text and ('MYMEMORY WARNING' in text or 'USAGELIMITS' in text)


def load_arb(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def save_arb(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
        f.write('\n')


def translate_batch(strings, target, source='en'):
    """Translate a batch of strings (joined by newline).
    Returns list of translated strings (None for failures)."""
    if not strings:
        return []
    batch_text = '\n'.join(strings)
    # MyMemory limit ~500 chars; if too long, fall back to per-string
    if len(batch_text) > 480:
        return [translate_single(s, target, source) for s in strings]

    params = urllib.parse.urlencode({
        'q': batch_text,
        'langpair': f'{source}|{target}',
        'de': next_email(),
    })
    url = f'https://api.mymemory.translated.net/get?{params}'
    try:
        result = subprocess.run(
            ['curl', '-s', '--max-time', '25', url],
            capture_output=True, text=True, timeout=35,
        )
        if result.returncode != 0:
            return [None] * len(strings)
        data = json.loads(result.stdout)
        translated = data.get('responseData', {}).get('translatedText', '')
        if not translated or is_quota_warning(translated):
            return [None] * len(strings)
        lines = translated.split('\n')
        target_is_cjk = target.startswith(('zh', 'ja', 'ko', 'yue'))
        results = []
        for i, orig in enumerate(strings):
            if i >= len(lines):
                results.append(None)
                continue
            t = lines[i].strip()
            if not t or t == orig or is_quota_warning(t):
                results.append(None)
                continue
            if not target_is_cjk and is_cjk(t):
                results.append(None)
                continue
            results.append(t)
        return results
    except Exception:
        return [None] * len(strings)


def translate_single(text, target, source='en'):
    """Translate a single string."""
    if not text or not text.strip():
        return text
    if len(text) > 450:
        return None
    params = urllib.parse.urlencode({
        'q': text,
        'langpair': f'{source}|{target}',
        'de': next_email(),
    })
    url = f'https://api.mymemory.translated.net/get?{params}'
    try:
        result = subprocess.run(
            ['curl', '-s', '--max-time', '20', url],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return None
        data = json.loads(result.stdout)
        translated = data.get('responseData', {}).get('translatedText')
        if not translated or not translated.strip():
            return None
        translated = translated.strip()
        if is_quota_warning(translated):
            return None
        target_is_cjk = target.startswith(('zh', 'ja', 'ko', 'yue'))
        if not target_is_cjk and is_cjk(translated):
            return None
        if translated == text:
            return None
        return translated
    except Exception:
        return None


def chunked(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i:i + size]


def get_missing_keys(zh_data, lang_data):
    zh_keys = {k for k in zh_data if not k.startswith('@')}
    lang_keys = {k for k in lang_data if not k.startswith('@')}
    missing = zh_keys - lang_keys
    return [(k, zh_data[k]) for k in sorted(missing)
            if isinstance(zh_data.get(k), str) and zh_data.get(k)]


def get_untranslated_keys(zh_data, en_data, lang_data):
    zh_keys = {k for k in zh_data if not k.startswith('@')}
    result = []
    for k in sorted(zh_keys):
        en_val = en_data.get(k)
        lang_val = lang_data.get(k)
        if not en_val or not isinstance(en_val, str):
            continue
        # Skip ICU pattern keys (plural/select/date/number) - keep English
        if any(p in en_val for p in (', plural,', ', select,', ', date,', ', number,')):
            continue
        if lang_val and lang_val == en_val:
            result.append((k, en_val))
    return result


def process_language(lang_code, zh_data, en_data, limit=None, retranslate=True,
                     workers=6, batch_size=6):
    arb_name = f'intl_{lang_code}.arb'
    arb_path = os.path.join(ARB_DIR, arb_name)
    if not os.path.exists(arb_path):
        print(f'  [skip] {arb_name} not found', flush=True)
        return

    data = load_arb(arb_path)
    missing = get_missing_keys(zh_data, data)
    for key, zh_value in missing:
        data[key] = en_data.get(key, zh_value)
        meta_key = f'@{key}'
        if meta_key not in data and meta_key in zh_data:
            data[meta_key] = zh_data[meta_key]
    if missing:
        save_arb(arb_path, data)

    if not retranslate:
        print(f'  [done] {arb_name}: +{len(missing)} fallback keys', flush=True)
        return

    to_translate = get_untranslated_keys(zh_data, en_data, data)
    if not to_translate:
        print(f'  [ok] {arb_name}: all keys translated', flush=True)
        return

    total = len(to_translate)
    if limit:
        to_translate = to_translate[:limit]
    print(f'  [translating] {arb_name}: {len(to_translate)}/{total} keys '
          f'(workers={workers}, batch={batch_size})', flush=True)

    target = LANG_MAP.get(lang_code, lang_code)
    source = 'zh' if lang_code in TRADITIONAL_TARGETS else 'en'

    # Build batches
    batches = list(chunked(to_translate, batch_size))
    added = 0
    failed = 0

    def do_batch(batch):
        keys = [k for k, _ in batch]
        values = [v for _, v in batch]
        results = translate_batch(values, target, source=source)
        return list(zip(keys, results))

    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(do_batch, b): i for i, b in enumerate(batches)}
        done_count = 0
        for future in as_completed(futures):
            try:
                results = future.result()
                for key, translated in results:
                    if translated is not None:
                        data[key] = translated
                        added += 1
                    else:
                        failed += 1
            except Exception:
                failed += len(batches[futures[future]])
            done_count += 1
            if done_count % 10 == 0 or done_count == len(batches):
                print(f'    ... {done_count}/{len(batches)} batches '
                      f'({added} translated, {failed} fallback)', flush=True)

    save_arb(arb_path, data)
    print(f'  [done] {arb_name}: {added} translated, {failed} English fallback',
          flush=True)


def main():
    only_lang = None
    limit = None
    retranslate = True
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == '--lang' and i + 1 < len(args):
            only_lang = args[i + 1]
            i += 2
        elif args[i] == '--limit' and i + 1 < len(args):
            limit = int(args[i + 1])
            i += 2
        elif args[i] == '--no-retranslate':
            retranslate = False
            i += 1
        else:
            i += 1

    zh_data = load_arb(ZH_FILE)
    en_data = load_arb(EN_FILE)

    all_langs = []
    for f in sorted(os.listdir(ARB_DIR)):
        if f.startswith('intl_') and f.endswith('.arb') and f != 'intl_zh.arb':
            all_langs.append(f[5:-4])

    if only_lang:
        all_langs = [only_lang] if only_lang in all_langs else []

    lang_counts = []
    for lang in all_langs:
        path = os.path.join(ARB_DIR, f'intl_{lang}.arb')
        if os.path.exists(path):
            data = load_arb(path)
            count = (len(get_untranslated_keys(zh_data, en_data, data))
                     if retranslate else len(get_missing_keys(zh_data, data)))
            lang_counts.append((count, lang))
    lang_counts.sort()

    print(f'Processing {len(lang_counts)} languages...', flush=True)
    for count, lang in lang_counts:
        if count == 0:
            print(f'[skip] {lang}: nothing to do', flush=True)
            continue
        label = 'untranslated' if retranslate else 'missing'
        print(f'\n=== {lang} ({count} {label}) ===', flush=True)
        process_language(lang, zh_data, en_data, limit=limit, retranslate=retranslate)

    print('\n=== Done ===', flush=True)


if __name__ == '__main__':
    main()
