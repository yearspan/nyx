import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';

/// V2 外观设置页
///
/// 仅提供主题模式选择：跟随系统 / 深色 / 浅色
class AppearanceV2 extends StatefulWidget {
  const AppearanceV2({super.key});

  @override
  State<AppearanceV2> createState() => _AppearanceV2State();
}

class _AppearanceV2State extends State<AppearanceV2> {
  void switchTheme(ThemeMode mode) {
    ThemeController.of(context).setThemeMode(mode);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final v2 = V2Theme.of(context);
    final currentTheme = ThemeController.of(context).themeMode;

    return Scaffold(
      backgroundColor: v2.scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.appearance),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    l10n.changeTheme,
                    style: TextStyle(
                      fontSize: 13,
                      color: v2.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _ThemeCard(
                  theme: v2,
                  options: [
                    _Option(
                      label: l10n.systemTheme,
                      value: ThemeMode.system,
                    ),
                    _Option(
                      label: l10n.darkTheme,
                      value: ThemeMode.dark,
                    ),
                    _Option(
                      label: l10n.lightTheme,
                      value: ThemeMode.light,
                    ),
                  ],
                  selectedValue: currentTheme,
                  onSelected: switchTheme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Option<T> {
  final String label;
  final T value;
  const _Option({required this.label, required this.value});
}

class _ThemeCard<T> extends StatelessWidget {
  final V2ThemeData theme;
  final List<_Option<T>> options;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  const _ThemeCard({
    required this.theme,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i != 0)
              Padding(
                padding: EdgeInsets.only(left: 16),
                child: Divider(height: 1, color: theme.divider),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(options[i].value),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          options[i].label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (selectedValue == options[i].value)
                        Icon(
                          Icons.check,
                          color: theme.accent,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
