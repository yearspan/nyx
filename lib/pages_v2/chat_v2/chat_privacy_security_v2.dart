import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2 群聊「隐私与安全」页面
///
/// 群主和管理员可在此设置：
/// - 群链接可见性（公开 / 私密）
/// - 历史消息可见范围
class ChatPrivacySecurityV2 extends StatefulWidget {
  final String roomId;

  const ChatPrivacySecurityV2({super.key, required this.roomId});

  @override
  State<ChatPrivacySecurityV2> createState() => _ChatPrivacySecurityV2State();
}

class _ChatPrivacySecurityV2State extends State<ChatPrivacySecurityV2> {
  Room get _room => Matrix.of(context).client.getRoomById(widget.roomId)!;

  bool _joinRulesLoading = false;
  bool _historyVisibilityLoading = false;

  Future<void> _setJoinRule(JoinRules rule) async {
    if (_joinRulesLoading) return;
    setState(() => _joinRulesLoading = true);
    try {
      await _room.setJoinRules(rule);
    } catch (e) {
      debugPrint('[PrivacySecurity] setJoinRule failed: $e');
      if (mounted) V2Toast.show(L10n.of(context).oopsSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _joinRulesLoading = false);
    }
  }

  Future<void> _setHistoryVisibility(HistoryVisibility visibility) async {
    if (_historyVisibilityLoading) return;
    setState(() => _historyVisibilityLoading = true);
    try {
      await _room.setHistoryVisibility(visibility);
    } catch (e) {
      debugPrint('[PrivacySecurity] setHistoryVisibility failed: $e');
      if (mounted) V2Toast.show(L10n.of(context).oopsSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _historyVisibilityLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = _room;
    final canEditJoinRules = room.canChangeJoinRules && !_joinRulesLoading;
    final canEditHistory = room.canChangeHistoryVisibility &&
        !_historyVisibilityLoading;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.privacyAndSecurity,
              backgroundColor: V2Theme.of(context).scaffoldBackground,
            ),
            Expanded(
              child: StreamBuilder<Object>(
                stream: room.client.onRoomState.stream.where(
                  (update) => update.roomId == room.id,
                ),
                builder: (context, snapshot) {
                  final joinRules = room.joinRules;
                  final historyVisibility = room.historyVisibility;
                  final isPublic = joinRules == JoinRules.public;
                  final canonicalAlias = room.canonicalAlias;
                  final matrixLocals = MatrixLocals(l10n);

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 20),
                        // 链接
                        Text(
                          l10n.link,
                          style: TextStyle(
                            fontSize: 13,
                            color: V2Theme.of(context).textSecondary,
                          ),
                        ),
                        SizedBox(height: 8),
                        _OptionCard(
                          children: [
                            _RadioOption(
                              label: l10n.anyoneCanJoin,
                              selected: isPublic,
                              enabled: canEditJoinRules,
                              onTap: () => _setJoinRule(JoinRules.public),
                            ),
                            _RadioOption(
                              label: l10n.invitedUsersOnly,
                              selected: !isPublic,
                              enabled: canEditJoinRules,
                              onTap: () => _setJoinRule(JoinRules.invite),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        if (!isPublic)
                        //   _buildPublicAlias(l10n, canonicalAlias)
                        // else
                          _buildInviteLink(l10n, room.id),

                        SizedBox(height: 24),
                        // 谁可以查看历史
                        Text(
                          l10n.visibilityOfTheChatHistory,
                          style: TextStyle(
                            fontSize: 13,
                            color: V2Theme.of(context).textSecondary,
                          ),
                        ),
                        SizedBox(height: 8),
                        _OptionCard(
                          children: [
                            for (final hv in HistoryVisibility.values)
                              _RadioOption(
                                label: hv.getLocalizedString(matrixLocals),
                                selected: historyVisibility == hv,
                                enabled: canEditHistory,
                                onTap: () => _setHistoryVisibility(hv),
                              ),
                          ],
                        ),
                        SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 公开群：展示主别名链接
  Widget _buildPublicAlias(L10n l10n, String canonicalAlias) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.tag,
                size: 18,
                color: V2Theme.of(context).textSecondary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  canonicalAlias.isNotEmpty ? canonicalAlias : l10n.user,
                  style: TextStyle(
                    fontSize: 15,
                    color: canonicalAlias.isNotEmpty
                        ? Theme.of(context).colorScheme.onSurface
                        : V2Theme.of(context).textSecondary,
                  ),
                ),
              ),
              if (canonicalAlias.isNotEmpty && PlatformInfos.isMobile)
                GestureDetector(
                  onTap: () => FluffyShare.share(
                    'https://nstalk.space/#/$canonicalAlias',
                    context,
                  ),
                  child: Icon(
                    Icons.ios_share,
                    size: 20,
                    color: V2Theme.of(context).accent,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 私密群：展示邀请链接 + 分享按钮
  Widget _buildInviteLink(L10n l10n, String roomId) {
    final inviteLink = 'https://nstalk.space/#/$roomId';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: V2Theme.of(context).cardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.link,
                size: 18,
                color: V2Theme.of(context).textSecondary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  inviteLink,
                  style: TextStyle(
                    fontSize: 14,
                    color: V2Theme.of(context).textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        if (PlatformInfos.isMobile)
          SizedBox(
            width: double.infinity,
            //height: 50,
            child: ElevatedButton(
              onPressed: () => FluffyShare.share(inviteLink, context),
              style: ElevatedButton.styleFrom(
                backgroundColor: V2Theme.of(context).accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: Text(
                l10n.shareInviteLink,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

/// 选项卡片（白底圆角，内部为多个可选项）
class _OptionCard extends StatelessWidget {
  final List<Widget> children;

  const _OptionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 0.5,
                color: V2Theme.of(context).divider,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

/// 带勾选图标的单选选项
class _RadioOption extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _RadioOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: selected
                  ? V2Theme.of(context).accent
                  : (enabled
                      ? V2Theme.of(context).textSecondary
                      : V2Theme.of(context).textSecondary.withValues(alpha: 0.4)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: enabled
                      ? Theme.of(context).colorScheme.onSurface
                      : V2Theme.of(context).textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
