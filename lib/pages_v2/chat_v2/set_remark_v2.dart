import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/remark.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

/// 设置备注页：备注为仅本地可见的好友别名，写入 account_data，不改变房间名
class SetRemarkV2 extends StatefulWidget {
  final String roomId;

  const SetRemarkV2({super.key, required this.roomId});

  @override
  State<SetRemarkV2> createState() => _SetRemarkV2State();
}

class _SetRemarkV2State extends State<SetRemarkV2> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final client = Matrix.of(context).client;
    final room = client.getRoomById(widget.roomId);
    final matrixId = room?.directChatMatrixID;
    final remark =
        matrixId != null ? RemarkStore.getRemark(client, matrixId) : null;
    _controller = TextEditingController(text: remark ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _controller.text.trim();
    setState(() => _saving = true);
    try {
      final client = Matrix.of(context).client;
      final room = client.getRoomById(widget.roomId);
      final matrixId = room?.directChatMatrixID;
      if (matrixId != null) {
        await RemarkStore.setRemark(client, matrixId, text);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        V2Toast.show('$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.setRemark,
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/v2/rooms');
                }
              },
              action: Padding(
                padding: EdgeInsets.only(right: 12),
                child: _saving
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : GestureDetector(
                        onTap: _save,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: V2Theme.of(context).accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            l10n.ok,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: V2Theme.of(context).cardBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLines: 1,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: l10n.setRemark,
                        hintStyle: TextStyle(
                          color: V2Theme.of(context).textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      l10n.remarkVisibleOnlyToYou,
                      style: TextStyle(
                        fontSize: 13,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
