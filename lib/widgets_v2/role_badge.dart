import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 群成员角色徽章（所有者 / 管理员 / 协管员）。
///
/// 统一 ChatMembersV2 与 RoomRoleMembersV2 的角色标签样式：
///  - 所有者：紫色
///  - 管理员：绿色
///  - 协管员：橙色
///
/// 普通成员（PowerLevelRole.user）不显示徽章。
class RoleBadge extends StatelessWidget {
  final PowerLevelRole role;

  /// 房间创建者即使存储权限不是最高级，也显示为「所有者」。
  final bool isOwner;

  const RoleBadge({super.key, required this.role, this.isOwner = false});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final (:label, :bg, :fg) = _style(l10n);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500),
      ),
    );
  }

  ({String label, Color bg, Color fg}) _style(L10n l10n) {
    if (isOwner || role == PowerLevelRole.owner) {
      return (
        label: l10n.owner,
        bg: Color(0xFFF3E8FF),
        fg: Color(0xFF8B5CF6),
      );
    }
    if (role == PowerLevelRole.admin) {
      return (
        label: l10n.admin,
        bg: Color(0xFFE8F5E9),
        fg: Color(0xFF2E7D32),
      );
    }
    return (
      label: l10n.moderator,
      bg: Color(0xFFFFF3E0),
      fg: Color(0xFFE65100),
    );
  }
}
