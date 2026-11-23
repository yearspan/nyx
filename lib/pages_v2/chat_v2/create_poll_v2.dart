import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_check_button.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_advanced_switch/flutter_advanced_switch.dart';
import 'package:matrix/matrix.dart';

/// V2 发起投票页（替代原版 StartPollBottomSheet）
///
/// 当传入 [pollEvent] 时为编辑模式：预填原投票内容，提交时撤回旧投票并新建；
/// 底部显示「删除投票」按钮。
class CreatePollV2 extends StatefulWidget {
  final Room room;
  final Event? pollEvent;
  const CreatePollV2({super.key, required this.room, this.pollEvent});

  @override
  State<CreatePollV2> createState() => _CreatePollV2State();
}

class _CreatePollV2State extends State<CreatePollV2> {
  late final TextEditingController _questionController;
  late final List<TextEditingController> _answerControllers;

  /// 隐藏投票：开启后投票结束才显示结果（PollKind.undisclosed）
  late bool _hiddenPoll;
  late final ValueNotifier<bool> _hiddenSwitchController;

  bool _canSubmit = false;
  bool _isSubmitting = false;
  String? _txid;

  bool get _isEditing => widget.pollEvent != null;

  static const int _maxAnswers = 10;

  @override
  void initState() {
    super.initState();
    final pollEvent = widget.pollEvent;
    if (pollEvent != null) {
      // 编辑模式：从原投票事件预填内容
      final content = pollEvent.parsedPollEventContent.pollStartContent;
      _questionController =
          TextEditingController(text: content.question.mText);
      _answerControllers = content.answers
          .map((a) => TextEditingController(text: a.mText))
          .toList();
      // 至少保留两个选项输入框
      while (_answerControllers.length < 2) {
        _answerControllers.add(TextEditingController());
      }
      _hiddenPoll = content.kind == PollKind.undisclosed;
    } else {
      _questionController = TextEditingController();
      _answerControllers = [
        TextEditingController(),
        TextEditingController(),
      ];
      _hiddenPoll = false;
    }
    _hiddenSwitchController = ValueNotifier(_hiddenPoll);
    _updateCanSubmit();
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _answerControllers) {
      c.dispose();
    }
    _hiddenSwitchController.dispose();
    super.dispose();
  }

  void _updateCanSubmit() {
    final questionOk = _questionController.text.trim().isNotEmpty;
    final answersOk = !_answerControllers.any(
      (c) => c.text.trim().isEmpty,
    );
    final newCan = questionOk && answersOk && !_isSubmitting;
    if (newCan != _canSubmit) setState(() => _canSubmit = newCan);
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
    final proceed = await showTrustUserInRoomDialog(context, widget.room);
    if (!proceed || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      _txid ??= widget.room.client.generateUniqueTransactionId();
      var id = 0;
      final answers = _answerControllers
          .map((c) => PollAnswer(id: (++id).toString(), mText: c.text.trim()))
          .toList();

      if (_isEditing) {
        // 编辑模式：先撤回旧投票，再新建
        try {
          await widget.pollEvent!.redactEvent();
        } catch (_) {}
      }

      await widget.room.startPoll(
        question: _questionController.text.trim(),
        answers: answers,
        kind: _hiddenPoll ? PollKind.undisclosed : PollKind.disclosed,
        maxSelections: 1,
        txid: _txid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deletePoll() async {
    final l10n = L10n.of(context);
    final confirmed = await V2ConfirmDialog.show(
      context,
      title: l10n.deletePoll,
      message: l10n.delete,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.pollEvent!.redactEvent();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    }
  }

  void _addAnswer() {
    if (_answerControllers.length >= _maxAnswers) return;
    setState(() => _answerControllers.add(TextEditingController()));
  }

  void _removeAnswer(int index) {
    if (_answerControllers.length <= 2) return;
    setState(() {
      _answerControllers.removeAt(index).dispose();
    });
    _updateCanSubmit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(
            title: l10n.startPoll,
            action: V2CheckButton(
              onTap: _submit,
              isLoading: _isSubmitting,
              enabled: _canSubmit,
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _buildSectionLabel(l10n.pollQuestion),
                _buildCard(
                  child: TextField(
                    controller: _questionController,
                    onChanged: (_) => _updateCanSubmit(),
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 1024,
                    decoration: InputDecoration(
                      hintText: l10n.pollQuestion,
                      hintStyle: TextStyle(color: V2Theme.of(context).textSecondary),
                      border: InputBorder.none,
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                _buildSectionLabel(l10n.answerOption),
                _buildCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < _answerControllers.length; i++)
                        _buildAnswerField(i, l10n),
                      if (_answerControllers.length < _maxAnswers)
                        InkWell(
                          onTap: _addAnswer,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  size: 20,
                                  color: V2Theme.of(context).accent,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  l10n.addAnswerOption,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: V2Theme.of(context).accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                _buildSectionLabel(l10n.settings),
                _buildCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.hiddenPoll,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                l10n.answersWillBeVisibleWhenPollHasEnded,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: V2Theme.of(context).textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AdvancedSwitch(
                          controller: _hiddenSwitchController,
                          activeColor: V2Theme.of(context).accent,
                          inactiveColor: Color(0xFFE5E5E5),
                          width: 50,
                          height: 30,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          onChanged: (value) =>
                              setState(() => _hiddenPoll = value as bool),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isEditing) ...[
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _deletePoll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: V2Theme.of(context).cardBackground,
                        foregroundColor: const Color(0xFFFF3B30),
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(V2Theme.radius),
                        ),
                      ),
                      child: Text(
                        l10n.deletePoll,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: V2Theme.of(context).textSecondary,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      ),
      child: child,
    );
  }

  Widget _buildAnswerField(int index, L10n l10n) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _answerControllers[index],
                  onChanged: (_) => _updateCanSubmit(),
                  maxLength: 64,
                  decoration: InputDecoration(
                    hintText: '${l10n.answerOption} ${index + 1}',
                    hintStyle:
                        TextStyle(color: V2Theme.of(context).textSecondary),
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_answerControllers.length > 2)
                IconButton(
                  icon: Icon(
                    Icons.cancel_outlined,
                    color: V2Theme.of(context).textSecondary,
                    size: 20,
                  ),
                  onPressed: () => _removeAnswer(index),
                ),
            ],
          ),
        ),
        if (index < _answerControllers.length - 1)
          Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}
