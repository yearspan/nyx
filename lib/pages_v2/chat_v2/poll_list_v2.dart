import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/create_poll_v2.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2 投票列表页（群聊设置 → 投票）
///
/// 两个标签页：进行中 / 已结束
/// 每个投票卡片展示问题、选项结果、日期、总票数，
/// 点击跳转到投票详情页；创建者可在进行中的投票卡片上结束投票。
class PollListV2 extends StatefulWidget {
  final String roomId;

  const PollListV2({super.key, required this.roomId});

  @override
  State<PollListV2> createState() => _PollListV2State();
}

class _PollListV2State extends State<PollListV2>
    with SingleTickerProviderStateMixin {
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  late final TabController _tabController;
  Timeline? _timeline;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTimeline();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTimeline() async {
    final r = room;
    if (r == null) return;
    try {
      _timeline = await r.getTimeline();
    } catch (_) {
      _timeline = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Event> get _pollEvents {
    final tl = _timeline;
    if (tl == null) return const [];
    return tl.events
        .where(
            (e) => e.type == PollEventContent.startType && !e.redacted)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final r = room;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(title: l10n.poll),
          // 标签栏（仿 iOS 分段控件样式，与媒体与文件页一致）
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                return Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Color(0xFF2C2C2E)
                        : Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      _buildSegmentTab(l10n.active, 0),
                      _buildSegmentTab(l10n.ended, 1),
                    ],
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : r == null
                    ? Center(child: Text(l10n.noMessagesYet))
                    : AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) {
                          return IndexedStack(
                            index: _tabController.index,
                            children: [
                              _buildPollList(l10n, ended: false),
                              _buildPollList(l10n, ended: true),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentTab(String label, int index) {
    final selected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_tabController.index == index) return;
          _tabController.animateTo(index);
        },
        child: Container(
          margin: EdgeInsets.all(3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : V2Theme.of(context).textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPollList(L10n l10n, {required bool ended}) {
    final polls = _pollEvents
        .where((e) => e.getPollHasBeenEnded(_timeline!) == ended)
        .toList();

    if (polls.isEmpty) {
      return Center(
        child: Text(
          l10n.noMessagesYet,
          style: TextStyle(color: V2Theme.of(context).textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: polls.length,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: _PollCard(
          event: polls[index],
          timeline: _timeline!,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CreatePollV2(
                  room: polls[index].room,
                  pollEvent: polls[index],
                ),
              ),
            );
            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
    );
  }
}

/// 投票卡片：问题、选项结果、日期、总票数、结束投票按钮
class _PollCard extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final VoidCallback onTap;

  const _PollCard({
    required this.event,
    required this.timeline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    PollEventContent? content;
    try {
      content = event.parsedPollEventContent;
    } catch (_) {
      content = null;
    }
    if (content == null) {
      return SizedBox.shrink();
    }

    final startContent = content.pollStartContent;
    final responses = event.getPollResponses(timeline);
    final ended = event.getPollHasBeenEnded(timeline);
    final answersVisible =
        startContent.kind == PollKind.disclosed || ended;
    final totalVotes = responses.length;
    final isCreator = event.senderId == event.room.client.userID;

    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.poll_outlined,
                  color: V2Theme.of(context).accent,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    startContent.question.mText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            ...startContent.answers.map((answer) {
              final votedUserIds = responses.entries
                  .where((e) => e.value.contains(answer.id))
                  .map((e) => e.key)
                  .toSet();
              final count = votedUserIds.length;
              final percent =
                  totalVotes == 0 ? 0.0 : count / totalVotes;
              final myVotes =
                  responses[event.room.client.userID!] ?? const <String>{};
              final voted = myVotes.contains(answer.id);

              return Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          voted
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: voted
                              ? V2Theme.of(context).accent
                              : V2Theme.of(context).textSecondary,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            answer.mText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: voted
                                  ? Theme.of(context).colorScheme.onSurface
                                  : V2Theme.of(context).textSecondary,
                            ),
                          ),
                        ),
                        if (answersVisible)
                          Text(
                            l10n.pollVotes(count),
                            style: TextStyle(
                              fontSize: 12,
                              color: V2Theme.of(context).textSecondary,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    if (answersVisible)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 4,
                          backgroundColor: V2Theme.of(context).divider,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            V2Theme.of(context).accent,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(event.originServerTs),
                  style: TextStyle(
                    fontSize: 12,
                    color: V2Theme.of(context).textSecondary,
                  ),
                ),
                if (answersVisible)
                  Text(
                    l10n.totalPollVotes(totalVotes),
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  )
                else
                  Text(
                    l10n.answersWillBeVisibleWhenPollHasEnded,
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
              ],
            ),
            if (isCreator && !ended) ...[
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: V2Theme.of(context).accent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(V2Theme.radius),
                    ),
                  ),
                  child: Text(l10n.editPoll),
                ),
              ),
            ],
          ],
        ),
    );
  }

  String _formatDate(DateTime ts) {
    final d = ts.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
