import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/settings_v2/notifications_v2.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_advanced_switch/flutter_advanced_switch.dart';
import 'package:go_router/go_router.dart';

class NotificationsV2View extends StatelessWidget {
  final NotificationsV2Controller controller;
  const NotificationsV2View(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.notifications),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: 12, bottom: 40),
              children: [
                // 总开关
                _SectionCard(
                  children: [
                    _SwitchTile(
                      title: l10n.notifyMeOnThisDevice,
                      value: controller.masterEnabled,
                      onToggle: controller.toggleMaster,
                      enabled: !controller.isLoading,
                    ),
                  ],
                ),
                SizedBox(height: 20),
                // 通知：群聊 / 私聊
                _SectionHeader(title: l10n.notifications),
                _SectionCard(
                  children: [
                    _NavigateTile(
                      title: l10n.groupChat,
                      trailing: _modeLabel(context, controller.groupChatMode),
                      onTap: () => context.push('/v2/notifications/group'),
                    ),
                    _Divider(),
                    _NavigateTile(
                      title: l10n.privateChat,
                      trailing: _modeLabel(context, controller.privateChatMode),
                      onTap: () => context.push('/v2/notifications/private'),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                // 提及
                _SectionHeader(title: l10n.mentions),
                _SectionCard(
                  children: [
                    _SwitchTile(
                      title: l10n.notifyMeWhenMentionedInGroup,
                      value: controller.mentionEnabled,
                      onToggle: controller.toggleMention,
                      enabled: !controller.isLoading,
                    ),
                  ],
                ),
                SizedBox(height: 20),
                // 更多设置
                _SectionHeader(title: l10n.moreSettings),
                _SectionCard(
                  children: [
                    _SwitchTile(
                      title: l10n.invite,
                      value: controller.inviteEnabled,
                      onToggle: controller.toggleInvite,
                      enabled: !controller.isLoading,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _modeLabel(BuildContext context, NotificationMode mode) {
    final l10n = L10n.of(context);
    return mode == NotificationMode.allMessages
        ? l10n.notifyAll
        : l10n.mentionsOnly;
  }
}

/// 分组标题
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          color: V2Theme.of(context).textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 圆角卡片容器
class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      ),
      child: Column(children: children),
    );
  }
}

/// 开关行
class _SwitchTile extends StatefulWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onToggle;
  final bool enabled;
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onToggle,
    this.enabled = true,
  });

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late final ValueNotifier<bool> _controller;

  /// 标记当前是否为「外部状态同步」导致的赋值。
  /// 此时只更新开关显示，不能触发 [onToggle]，否则会在 build 阶段
  /// （didUpdateWidget）调用业务回调里的 setState，抛
  /// "setState() called during build"，并造成重复请求。
  bool _programmaticallyUpdating = false;

  @override
  void initState() {
    super.initState();
    _controller = ValueNotifier<bool>(widget.value);
  }

  @override
  void didUpdateWidget(covariant _SwitchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.value != widget.value) {
      _programmaticallyUpdating = true;
      _controller.value = widget.value;
      _programmaticallyUpdating = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          AdvancedSwitch(
            controller: _controller,
            activeColor: V2Theme.of(context).accent,
            inactiveColor: Color(0xFFE5E5E5),
            width: 50,
            height: 30,
            enabled: widget.enabled,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
            onChanged: (v) {
              if (_programmaticallyUpdating) return;
              widget.onToggle(v as bool);
            },
          ),
        ],
      ),
    );
  }
}

/// 跳转行（右侧文字 + 箭头）
class _NavigateTile extends StatelessWidget {
  final String title;
  final String trailing;
  final VoidCallback onTap;
  const _NavigateTile({
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
            Text(
              trailing,
              style: TextStyle(fontSize: 14, color: V2Theme.of(context).textSecondary),
            ),
            SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: V2Theme.of(context).textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: V2Theme.of(context).divider),
    );
  }
}
