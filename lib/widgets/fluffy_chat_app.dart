import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/layouts/call_overlay.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/custom_scroll_behaviour.dart';
import 'matrix.dart';

class FluffyChatApp extends StatefulWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final ({String? pincode, bool useBiometrics}) appLockSettings;
  final SharedPreferences store;

  const FluffyChatApp({
    super.key,
    this.testWidget,
    required this.clients,
    required this.store,
    required this.appLockSettings,
  });

  /// getInitialLink may rereturn the value multiple times if this view is
  /// opened multiple times for example if the user logs out after they logged
  /// in with qr code or magic link.
  static bool gotInitialLink = false;

  // Router must be outside of build method so that hot reload does not reset
  // the current path.
  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Workaround for content sharings passed to go router:
      if ({
        'content',
        'sharemedia-im.nyx.app',
      }.contains(state.uri.scheme)) {
        Logs().d('Ignore content sharing handling in go router', state.uri);
        return '/';
      }

      // Pass deep links and invite links (https://nstalk.space/#/...) to the
      // new private chat page for resolving:
      final uriStr = state.uri.toString();
      final lower = uriStr.toLowerCase();
      if (uriStr.startsWith(AppConfig.deepLinkPrefix) ||
          lower.startsWith(AppConfig.inviteLinkPrefix)) {
        return '/v2/new-private-chat#${state.uri}';
      }
      return null;
    },
  );

  /// 解析存储的语言字符串为 Locale，空串返回 null（跟随系统）。
  /// 支持 `zh`、`zh_Hant`、`yue_Hant`、`pt_BR` 等格式。
  static Locale? parseLocale(String? code) {
    if (code == null || code.isEmpty) return null;
    final parts = code.split('_');
    if (parts.length == 1) {
      return Locale(parts[0]);
    }
    if (parts.length == 2) {
      // 第二段可能是 scriptCode（如 Hant）或 countryCode（如 BR）
      final second = parts[1];
      if (second.length <= 3) {
        // 长度 <=3 视为国家/地区码
        return Locale.fromSubtags(
          languageCode: parts[0],
          countryCode: second,
        );
      }
      return Locale.fromSubtags(
        languageCode: parts[0],
        scriptCode: second,
      );
    }
    return Locale.fromSubtags(
      languageCode: parts[0],
      scriptCode: parts[1],
      countryCode: parts[2],
    );
  }

  /// 获取系统当前首选 locale
  static Locale systemLocale() {
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    return locales.isNotEmpty ? locales.first : const Locale('en');
  }

  /// 切换应用语言，[locale] 为 null 时表示跟随系统
  static Future<void> changeLanguage(
    BuildContext context,
    Locale? locale,
  ) async {
    final code = locale == null
        ? ''
        : [
            locale.languageCode,
            if (locale.scriptCode != null) locale.scriptCode,
            if (locale.countryCode != null) locale.countryCode,
          ].join('_');
    await AppSettings.language.setItem(code);
    if (context.mounted) {
      // 跟随系统时显式传入系统当前 locale，而非 null，
      // 避免 MaterialApp.locale 从非 null 切到 null 时框架解析失败
      context.findAncestorStateOfType<_FluffyChatAppState>()?._applyLocale(
        locale ?? systemLocale(),
      );
    }
  }

  @override
  State<FluffyChatApp> createState() => _FluffyChatAppState();
}

class _FluffyChatAppState extends State<FluffyChatApp>
    with WidgetsBindingObserver {
  Locale? _locale;

  // 主题缓存：避免每次 ThemeBuilder 重建都重新执行 ColorScheme.fromSeed
  // （rainbow variant 涉及整套 HCT 色板计算）。仅在 seed 或窗口宽度变化时重建。
  ThemeData? _cachedLightTheme;
  ThemeData? _cachedDarkTheme;
  Color? _cachedSeed;
  double? _cachedViewWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final saved = AppSettings.language.value;
    // 保存值为空表示跟随系统，此时显式取系统当前 locale，
    // 避免 MaterialApp.locale 为 null 时框架解析异常
    _locale = saved.isEmpty
        ? FluffyChatApp.systemLocale()
        : FluffyChatApp.parseLocale(saved);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    // 当前设置为"跟随系统"时，系统语言变化需同步更新应用语言
    if (AppSettings.language.value.isEmpty &&
        locales != null &&
        locales.isNotEmpty) {
      _applyLocale(locales.first);
    }
  }

  void _applyLocale(Locale? locale) {
    if (!mounted) return;
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder: (context, themeMode, primaryColor) {
        final viewWidth = View.of(context).physicalSize.width /
            View.of(context).devicePixelRatio;
        final ThemeData lightTheme;
        final ThemeData darkTheme;
        if (_cachedLightTheme != null &&
            _cachedSeed == primaryColor &&
            _cachedViewWidth == viewWidth) {
          lightTheme = _cachedLightTheme!;
          darkTheme = _cachedDarkTheme!;
        } else {
          lightTheme = FluffyThemes.buildTheme(
            context,
            Brightness.light,
            primaryColor,
          );
          darkTheme = FluffyThemes.buildTheme(
            context,
            Brightness.dark,
            primaryColor,
          );
          _cachedLightTheme = lightTheme;
          _cachedDarkTheme = darkTheme;
          _cachedSeed = primaryColor;
          _cachedViewWidth = viewWidth;
        }
        return MaterialApp.router(
          title: AppSettings.applicationName.value,
          themeMode: themeMode,
          locale: _locale,
          theme: lightTheme,
          darkTheme: darkTheme,
        scrollBehavior: CustomScrollBehavior(),
        localizationsDelegates: [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
          ...GlobalCupertinoLocalizations.delegates,
          // Flutter 内置的 Material/Cupertino 本地化不支持粤语（yue）等语言，
          // 会导致 TextField 等组件因找不到 MaterialLocalizations 而崩溃。
          // 这里在全局委托不支持当前 locale 时回退到繁体中文（与粤语同属中文圈），
          // 应用自身的 L10n 字符串仍保持粤语。
          const _FallbackMaterialLocalizationsDelegate(),
          const _FallbackCupertinoLocalizationsDelegate(),
        ],
        supportedLocales: L10n.supportedLocales,
        routerConfig: FluffyChatApp.router,
        builder: EasyLoading.init(
          builder: (context, child) => _EasyLoadingThemeSync(
            child: AppLockWidget(
              pincode: widget.appLockSettings.pincode,
              useBiometrics: widget.appLockSettings.useBiometrics,
              isLoggedIn: widget.clients.any((client) => client.isLogged()),
              // Need a navigator above the Matrix widget for
              // displaying dialogs
              child: Matrix(
                clients: widget.clients,
                store: widget.store,
                child: CallOverlay(
                  child:
                      widget.testWidget ??
                      Scaffold(
                        body: GestureDetector(
                          onTap: () {
                            hideKeyboard(context);
                          },
                          child: child,
                        ),
                        resizeToAvoidBottomInset: false,
                      ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    );
  }
}

void hideKeyboard(BuildContext context) {
  final currentFocus = FocusScope.of(context);
  if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}

/// 同步 EasyLoading（V2Toast 底层）样式到当前主题深浅色
///
/// flutter_easyloading 默认使用固定的 dark/light 配色，不跟随应用主题。
/// 这里在主题变化时把背景、文字、指示器颜色刷成 V2Theme 的对应值。
class _EasyLoadingThemeSync extends StatefulWidget {
  final Widget child;

  const _EasyLoadingThemeSync({required this.child});

  @override
  State<_EasyLoadingThemeSync> createState() => _EasyLoadingThemeSyncState();
}

class _EasyLoadingThemeSyncState extends State<_EasyLoadingThemeSync> {
  Brightness? _lastBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness == brightness) return;
    _lastBrightness = brightness;
    _applyTheme();
  }

  void _applyTheme() {
    final v2 = V2Theme.of(context);
    // Toast / Loading 颜色由 V2Toast.applyTheme 根据明暗主题单独管理
    // （Toast 采用反色，Loading 保持卡片底色）
    V2Toast.applyTheme(context);
    EasyLoading.instance
      ..loadingStyle = EasyLoadingStyle.custom
      ..backgroundColor = v2.cardBackground
      ..textColor = Theme.of(context).colorScheme.onSurface
      ..indicatorColor = v2.accent
      ..progressColor = v2.accent
      ..maskType = EasyLoadingMaskType.none
      ..radius = 12.0
      ..contentPadding = const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 为 Flutter 内置本地化不支持的语言（如粤语 yue）提供 [MaterialLocalizations] 回退。
///
/// `GlobalMaterialLocalizations.delegate` 只支持 `kMaterialSupportedLanguages`
/// 中列出的语言，粤语 `yue` 不在其中。这会导致 [TextField] 等组件在构建时
/// 调用 `debugCheckHasMaterialLocalizations` 失败（`Localizations.of<MaterialLocalizations>`
/// 返回 null）而崩溃。
///
/// 此委托排在 `GlobalMaterialLocalizations.delegate` 之后，仅在全局委托不支持
/// 当前 locale 时生效，回退加载繁体中文（`zh_HK`，与粤语同属中文圈）的
/// Material 文案；应用自身的 L10n 字符串仍保持用户选择的语言。
class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      !GlobalMaterialLocalizations.delegate.isSupported(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    final fallback = locale.languageCode == 'yue'
        ? const Locale('zh', 'HK')
        : const Locale('en');
    return GlobalMaterialLocalizations.delegate.load(fallback);
  }

  @override
  bool shouldReload(_) => false;
}

/// 为 Flutter 内置本地化不支持的语言（如粤语 yue）提供 [CupertinoLocalizations] 回退。
///
/// 与 [_FallbackMaterialLocalizationsDelegate] 同理，`GlobalCupertinoLocalizations.delegate`
/// 也不支持 `yue`，需要回退到繁体中文以提供 Cupertino 组件所需的本地化文案。
class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      !GlobalCupertinoLocalizations.delegate.isSupported(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    final fallback = locale.languageCode == 'yue'
        ? const Locale('zh', 'HK')
        : const Locale('en');
    return GlobalCupertinoLocalizations.delegate.load(fallback);
  }

  @override
  bool shouldReload(_) => false;
}
