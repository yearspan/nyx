import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 自己发送消息的状态标识：发送中 / 发送失败 / 未读 / 已读
///
/// - 发送中：转圈
/// - 发送失败：红色感叹号
/// - 已发送未读：单勾
/// - 对方已读：双勾（浅蓝色）
class MessageStatusIcon extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final double size;
  final Color color; // 未读状态下图标颜色（通常是气泡内的文字色）

  const MessageStatusIcon({
    super.key,
    required this.event,
    required this.timeline,
    this.size = 14,
    this.color = Colors.white,
  });

  /// 判断该事件是否已被其他成员读。
  ///
  /// timeline.events 按最新在前排列（index 0 最新）。
  /// 其他人的公开读回执（m.read）指向他读到的最新事件，
  /// 只要该事件的位置与当前事件相同或更新（索引更小或相等），即视为已读。
  static bool isRead(Event event, Timeline timeline) {
    final myUserId = event.room.client.userID;
    final events = timeline.events;

    final indexById = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      indexById[events[i].eventId] = i;
    }

    final myIndex = indexById[event.eventId];
    if (myIndex == null) return false;

    final otherReceipts = event.room.receiptState.global.otherUsers;
    for (final entry in otherReceipts.entries) {
      if (entry.key == myUserId) continue;
      final receiptIndex = indexById[entry.value.eventId];
      // 回执指向的事件与本事件同位置或更新 => 已读
      if (receiptIndex != null && receiptIndex <= myIndex) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 发送中
    if (event.status == EventStatus.sending) {
      return SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: EdgeInsets.all(size * 0.15),
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      );
    }

    // 发送失败：红色感叹号，点击弹出「重发 / 删除」
    if (event.status == EventStatus.error) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showFailedMessageActions(context),
        child: Padding(
          padding: EdgeInsets.all(2),
          child: Icon(
            Icons.error_outline,
            size: size + 2,
            color: Colors.redAccent,
          ),
        ),
      );
    }

    if (isRead(event, timeline)) {
      // 双勾：已读（WhatsApp 风格浅蓝色）
      return Icon(
        Icons.done_all,
        size: size,
        color: color,
      );
    }

    // 单勾：已发送，对方未读
    return Icon(Icons.check, size: size, color: color);
  }

  /// 发送失败消息的操作菜单：重发 / 删除
  Future<void> _showFailedMessageActions(BuildContext context) async {
    final l10n = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: V2Theme.of(context).cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) {
        Widget row(
          IconData icon,
          String label,
          Color tint,
          VoidCallback onTap,
        ) {
          return InkWell(
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 18,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 24, color: tint),
                  SizedBox(width: 16),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: tint,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 8),
              // 重发
              row(
                Icons.refresh,
                l10n.tryAgain,
                Theme.of(context).colorScheme.onSurface,
                event.sendAgain,
              ),
              // 删除本地未发出的消息
              row(
                Icons.delete_outline,
                l10n.delete,
                Colors.redAccent,
                event.cancelSend,
              ),
              SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
