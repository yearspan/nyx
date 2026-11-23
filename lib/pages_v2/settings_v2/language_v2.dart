import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';

/// V2 语言选择页
class LanguageV2 extends StatefulWidget {
  const LanguageV2({super.key});

  @override
  State<LanguageV2> createState() => _LanguageV2State();
}

class _LanguageV2State extends State<LanguageV2> {
  /// 可选语言列表（按语言代码排序，跟随系统置于首位）
  static final List<_LanguageOption> _options = [
    const _LanguageOption(name: '跟随系统', locale: null),
    ..._allLanguages,
  ];

  /// 判断两个 Locale 是否等价（languageCode / scriptCode / countryCode）
  bool _localeEquals(Locale? a, Locale? b) {
    if (a == null || b == null) return a == b;
    return a.languageCode == b.languageCode &&
        a.scriptCode == b.scriptCode &&
        a.countryCode == b.countryCode;
  }


  Future<void> _selectLanguage(_LanguageOption option) async {
    await FluffyChatApp.changeLanguage(context, option.locale);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final currentLocale = Localizations.localeOf(context);

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.language),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    l10n.selectLanguage,
                    style: TextStyle(
                      fontSize: 13,
                      color: V2Theme.of(context).textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: V2Theme.of(context).cardBackground,
                    borderRadius: BorderRadius.circular(V2Theme.cardRadius),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    children: [
                      for (var i = 0; i < _options.length; i++) ...[
                        if (i != 0)
                          Padding(
                            padding: EdgeInsets.only(left: 16),
                            child: Divider(height: 1, color: V2Theme.of(context).divider),
                          ),
                        _LanguageTile(
                          option: _options[i],
                          selected: _localeEquals(_options[i].locale, currentLocale),
                          onTap: () => _selectLanguage(_options[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 全部支持的语言（语言名称使用各语言母语写法）
const List<_LanguageOption> _allLanguages = [
  _LanguageOption(name: 'العربية', locale: Locale('ar')),
  _LanguageOption(name: 'Azərbaycan', locale: Locale('az')),
  _LanguageOption(name: 'Беларуская', locale: Locale('be')),
  _LanguageOption(name: 'বাংলা', locale: Locale('bn')),
  _LanguageOption(name: 'བོད་སྐད', locale: Locale('bo')),
  _LanguageOption(name: 'Català', locale: Locale('ca')),
  _LanguageOption(name: 'Čeština', locale: Locale('cs')),
  _LanguageOption(name: 'Dansk', locale: Locale('da')),
  _LanguageOption(name: 'Deutsch', locale: Locale('de')),
  _LanguageOption(name: 'Ελληνικά', locale: Locale('el')),
  _LanguageOption(name: 'English', locale: Locale('en')),
  _LanguageOption(name: 'Esperanto', locale: Locale('eo')),
  _LanguageOption(name: 'Español', locale: Locale('es')),
  _LanguageOption(name: 'Eesti', locale: Locale('et')),
  _LanguageOption(name: 'Euskara', locale: Locale('eu')),
  _LanguageOption(name: 'فارسی', locale: Locale('fa')),
  _LanguageOption(name: 'Suomi', locale: Locale('fi')),
  _LanguageOption(name: 'Filipino', locale: Locale('fil')),
  _LanguageOption(name: 'Français', locale: Locale('fr')),
  _LanguageOption(name: 'Gaeilge', locale: Locale('ga')),
  _LanguageOption(name: 'Galego', locale: Locale('gl')),
  _LanguageOption(name: 'עברית', locale: Locale('he')),
  _LanguageOption(name: 'हिन्दी', locale: Locale('hi')),
  _LanguageOption(name: 'Hrvatski', locale: Locale('hr')),
  _LanguageOption(name: 'Magyar', locale: Locale('hu')),
  _LanguageOption(name: 'Interlingua', locale: Locale('ia')),
  _LanguageOption(name: 'Bahasa Indonesia', locale: Locale('id')),
  _LanguageOption(name: 'Interlingue', locale: Locale('ie')),
  _LanguageOption(name: 'Italiano', locale: Locale('it')),
  _LanguageOption(name: '日本語', locale: Locale('ja')),
  _LanguageOption(name: 'ქართული', locale: Locale('ka')),
  _LanguageOption(name: 'Taqbaylit', locale: Locale('kab')),
  _LanguageOption(name: '한국어', locale: Locale('ko')),
  _LanguageOption(name: 'Latina', locale: Locale('la')),
  _LanguageOption(name: 'Lietuvių', locale: Locale('lt')),
  _LanguageOption(name: 'Latviešu', locale: Locale('lv')),
  _LanguageOption(name: 'Norsk Bokmål', locale: Locale('nb')),
  _LanguageOption(name: 'Nederlands', locale: Locale('nl')),
  _LanguageOption(name: 'Polski', locale: Locale('pl')),
  _LanguageOption(name: 'Português', locale: Locale('pt')),
  _LanguageOption(name: 'Português (Brasil)', locale: Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR')),
  _LanguageOption(name: 'Português (Portugal)', locale: Locale.fromSubtags(languageCode: 'pt', countryCode: 'PT')),
  _LanguageOption(name: 'Română', locale: Locale('ro')),
  _LanguageOption(name: 'Русский', locale: Locale('ru')),
  _LanguageOption(name: 'Slovenčina', locale: Locale('sk')),
  _LanguageOption(name: 'Slovenščina', locale: Locale('sl')),
  _LanguageOption(name: 'Shqip', locale: Locale('sq')),
  _LanguageOption(name: 'Српски', locale: Locale('sr')),
  _LanguageOption(name: 'Svenska', locale: Locale('sv')),
  _LanguageOption(name: 'தமிழ்', locale: Locale('ta')),
  _LanguageOption(name: 'తెలుగు', locale: Locale('te')),
  _LanguageOption(name: 'ไทย', locale: Locale('th')),
  _LanguageOption(name: 'Türkçe', locale: Locale('tr')),
  _LanguageOption(name: 'Українська', locale: Locale('uk')),
  _LanguageOption(name: "O'zbek", locale: Locale('uz')),
  _LanguageOption(name: 'Tiếng Việt', locale: Locale('vi')),
  _LanguageOption(name: '粵語', locale: Locale.fromSubtags(languageCode: 'yue', scriptCode: 'Hant')),
  _LanguageOption(name: '简体中文', locale: Locale('zh')),
  _LanguageOption(name: '繁體中文', locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
];

/// 语言选项数据
class _LanguageOption {
  final String name;
  final Locale? locale;

  const _LanguageOption({required this.name, required this.locale});
}

/// 单个语言选项
class _LanguageTile extends StatelessWidget {
  final _LanguageOption option;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  color: V2Theme.of(context).accent,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
