import 'package:fluffychat/config/v2_theme.dart';
import 'package:material_ui/material_ui.dart';

/// V2 统一搜索框组件（搜索图标 + 居中 + 主题色正文 #8D8D93 hint）
class V2SearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? contentPadding;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const V2SearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: v2.cardBackground,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: v2.divider),
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitted?.call(),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 16, color: v2.textSecondary),
            prefixIcon: Image.asset(
              "assets/images/common/search.png",
              width: 16,
            ),
            border: InputBorder.none,
            contentPadding: contentPadding,
          ),
        ),
      ),
    );
  }
}
