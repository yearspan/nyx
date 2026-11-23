import 'package:collection/collection.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeBuilder extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    ThemeMode themeMode,
    Color? primaryColor,
  )
  builder;

  final String themeModeSettingsKey;
  final String primaryColorSettingsKey;

  const ThemeBuilder({
    required this.builder,
    this.themeModeSettingsKey = 'theme_mode',
    this.primaryColorSettingsKey = 'primary_color',
    super.key,
  });

  @override
  State<ThemeBuilder> createState() => ThemeController();
}

class ThemeController extends State<ThemeBuilder> {
  SharedPreferences? _sharedPreferences;
  ThemeMode? _themeMode;
  Color? _primaryColor;

  ThemeMode get themeMode => _themeMode ?? ThemeMode.system;

  Color? get primaryColor => _primaryColor;

  static ThemeController of(BuildContext context) =>
      Provider.of<ThemeController>(context, listen: false);

  Future<void> _loadData(_) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();

    final rawThemeMode = preferences.getString(widget.themeModeSettingsKey);
    final rawColor = preferences.getInt(widget.primaryColorSettingsKey);

    setState(() {
      _themeMode = ThemeMode.values.singleWhereOrNull(
        (value) => value.name == rawThemeMode,
      );
      _primaryColor = rawColor == null ? null : Color(rawColor);
    });
  }

  /// 切换主题模式。
  ///
  /// 先同步 setState 更新 UI（让主题立即生效），再异步写入 SharedPreferences，
  /// 避免等待磁盘 I/O 导致切换延迟数秒。持久化失败不影响当前 UI 状态。
  Future<void> setThemeMode(ThemeMode newThemeMode) async {
    setState(() {
      _themeMode = newThemeMode;
    });
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setString(widget.themeModeSettingsKey, newThemeMode.name);
  }

  /// 设置主题主色。同样先更新 UI 再异步持久化。
  Future<void> setPrimaryColor(Color? newPrimaryColor) async {
    setState(() {
      _primaryColor = newPrimaryColor;
    });
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    if (newPrimaryColor == null) {
      await preferences.remove(widget.primaryColorSettingsKey);
    } else {
      await preferences.setInt(
        widget.primaryColorSettingsKey,
        newPrimaryColor.hexValue,
      );
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback(_loadData);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => this,
      child: DynamicColorBuilder(
        builder: (light, _) =>
            widget.builder(context, themeMode, primaryColor ?? light?.primary),
      ),
    );
  }
}
