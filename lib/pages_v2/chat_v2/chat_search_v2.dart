import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_media_files_v2.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_search_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

/// V2 聊天内搜索页
///
/// 三个标签页：消息 / 图库 / 文件
/// - 消息：按关键词搜索文本，结果列表展示发送者、时间、内容预览，点击跳转
/// - 图库：所有图片与视频，按月份分组的三方格缩略图
/// - 文件：所有非媒体附件，列表展示文件名、大小、类型，点击下载
class ChatSearchV2 extends StatefulWidget {
  final String roomId;

  const ChatSearchV2({super.key, required this.roomId});

  @override
  State<ChatSearchV2> createState() => _ChatSearchV2State();
}

class _ChatSearchV2State extends State<ChatSearchV2>
    with SingleTickerProviderStateMixin {
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  final List<Event> _messages = [];
  final List<Event> _images = [];
  final List<Event> _files = [];
  String? _messagesNextBatch, _imagesNextBatch, _filesNextBatch;
  bool _messagesEndReached = false;
  bool _imagesEndReached = false;
  bool _filesEndReached = false;
  bool _isLoading = false;
  DateTime? _searchedUntil;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 0) {
      _restartSearch();
    } else {
      _startSearch();
    }
  }

  /// 清空当前标签结果并重新搜索
  void _restartSearch() {
    setState(() {
      _messages.clear();
      _images.clear();
      _files.clear();
      _messagesNextBatch =
          _imagesNextBatch = _filesNextBatch = _searchedUntil = null;
      _messagesEndReached = _imagesEndReached = _filesEndReached = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSearch());
  }

  Future<void> _startSearch() async {
    if (_isLoading) return;
    final room = this.room;
    if (room == null) return;
    final l10n = L10n.of(context);

    switch (_tabController.index) {
      case 0: // 消息
        if (_messagesEndReached) return;
        final query = _searchController.text.trim();
        if (query.isEmpty) return;
        setState(() => _isLoading = true);
        try {
          final result = await room.searchEvents(
            searchTerm: query,
            nextBatch: _messagesNextBatch,
          );
          if (!mounted) return;
          setState(() {
            _messages.addAll(result.events);
            _messagesNextBatch = result.nextBatch;
            _messagesEndReached = result.nextBatch == null;
            _searchedUntil = result.searchedUntil;
          });
        } catch (_) {
          if (mounted) V2Toast.show(l10n.oopsSomethingWentWrong);
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
        break;
      case 1: // 图库
        if (_imagesEndReached) return;
        setState(() => _isLoading = true);
        try {
          final result = await room.searchEvents(
            searchFunc: (event) => {
              MessageTypes.Image,
              MessageTypes.Video,
            }.contains(event.messageType),
            nextBatch: _imagesNextBatch,
          );
          if (!mounted) return;
          setState(() {
            _images.addAll(result.events);
            _imagesNextBatch = result.nextBatch;
            _imagesEndReached = result.nextBatch == null;
            _searchedUntil = result.searchedUntil;
          });
        } catch (_) {
          if (mounted) V2Toast.show(l10n.oopsSomethingWentWrong);
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
        break;
      case 2: // 文件
        if (_filesEndReached) return;
        setState(() => _isLoading = true);
        try {
          final result = await room.searchEvents(
            searchFunc: (event) =>
                event.messageType == MessageTypes.File ||
                (event.messageType == MessageTypes.Audio &&
                    !event.content.containsKey('org.matrix.msc3245.voice')),
            nextBatch: _filesNextBatch,
          );
          if (!mounted) return;
          setState(() {
            _files.addAll(result.events);
            _filesNextBatch = result.nextBatch;
            _filesEndReached = result.nextBatch == null;
            _searchedUntil = result.searchedUntil;
          });
        } catch (_) {
          if (mounted) V2Toast.show(l10n.oopsSomethingWentWrong);
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
        break;
    }
  }

  /// 当前激活标签是否已加载到末尾
  bool get _currentEndReached {
    switch (_tabController.index) {
      case 0:
        return _messagesEndReached;
      case 1:
        return _imagesEndReached;
      case 2:
        return _filesEndReached;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = this.room;

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              title: l10n.search,
              onBack: () => context.pop(),
            ),
            V2SearchBar(
              controller: _searchController,
              hintText: l10n.search,
              onSubmitted: _restartSearch,
            ),
            Container(
              height: 44,
              margin: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: V2Theme.of(context).cardBackground,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TabBar(
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                controller: _tabController,
                indicator: BoxDecoration(
                  color: V2Theme.of(context).accent,
                  borderRadius: BorderRadius.circular(22),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: V2Theme.of(context).textSecondary,
                labelStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(text: l10n.messages),
                  Tab(text: l10n.gallery),
                  Tab(text: l10n.files),
                ],
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              child: room == null
                  ? Center(child: Text(l10n.youAreNoLongerParticipatingInThisChat))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildMessageTab(l10n, room),
                        _buildGalleryTab(l10n, room),
                        _buildFilesTab(l10n, room),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 消息标签 ====================

  Widget _buildMessageTab(L10n l10n, Room room) {
    if (_messages.isEmpty && _searchController.text.trim().isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_outlined,
        text: l10n.searchIn(
          room.getLocalizedDisplayname(MatrixLocals(l10n)),
        ),
      );
    }
    if (_messages.isEmpty && !_isLoading) {
      return _buildEmptyState(
        icon: Icons.search_off_outlined,
        text: l10n.userNotFound,
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: _messages.length + 1,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: V2Theme.of(context).divider),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return _buildSearchFooter(l10n);
        }
        final event = _messages[i];
        final sender = event.senderFromMemoryOrFallback;
        final displayname = sender.calcDisplayname(
          i18n: MatrixLocals(l10n),
        );
        return InkWell(
          onTap: () => context.go(
            '/v2/rooms/chat/${widget.roomId}?event=${event.eventId}',
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(
                  mxContent: sender.avatarUrl,
                  name: displayname,
                  size: 36,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            event.originServerTs.localizedTimeShort(context),
                            style: TextStyle(
                              fontSize: 12,
                              color: V2Theme.of(context).textSecondary,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Linkify(
                        text: event
                            .calcLocalizedBodyFallback(
                              plaintextBody: true,
                              removeMarkdown: true,
                              MatrixLocals(l10n),
                            )
                            .trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: V2Theme.of(context).textSecondary,
                        ),
                        linkStyle: TextStyle(
                          color: V2Theme.of(context).accent,
                          decoration: TextDecoration.underline,
                        ),
                        onOpen: (url) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== 图库标签 ====================

  Widget _buildGalleryTab(L10n l10n, Room room) {
    if (_images.isEmpty && !_isLoading) {
      return _buildEmptyState(
        icon: Icons.photo_library_outlined,
        text: l10n.noMedia,
      );
    }

    final eventsByMonth = <DateTime, List<Event>>{};
    for (final event in _images) {
      final month = DateTime(
        event.originServerTs.year,
        event.originServerTs.month,
      );
      eventsByMonth[month] ??= [];
      eventsByMonth[month]!.add(event);
    }
    final monthEntries = eventsByMonth.entries.toList();

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 8),
      itemCount: monthEntries.length + 1,
      itemBuilder: (context, i) {
        if (i == monthEntries.length) {
          return _buildSearchFooter(l10n);
        }
        final monthEvents = monthEntries[i].value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(height: 1, color: V2Theme.of(context).divider),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    DateFormat.yMMMM(
                      safeDateFormatLocale(context),
                    ).format(monthEntries[i].key),
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(height: 1, color: V2Theme.of(context).divider),
                ),
              ],
            ),
            SizedBox(height: 8),
            GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              clipBehavior: Clip.hardEdge,
              crossAxisCount: 3,
              children: monthEvents
                  .map((event) => MediaThumbnail(event: event))
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  // ==================== 文件标签 ====================

  Widget _buildFilesTab(L10n l10n, Room room) {
    if (_files.isEmpty && !_isLoading) {
      return _buildEmptyState(
        icon: Icons.folder_outlined,
        text: l10n.noFiles,
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: _files.length + 1,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: V2Theme.of(context).divider,
        indent: 56,
      ),
      itemBuilder: (context, i) {
        if (i == _files.length) {
          return _buildSearchFooter(l10n);
        }
        return FileTile(event: _files[i]);
      },
    );
  }

  // ==================== 通用组件 ====================

  Widget _buildEmptyState({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: V2Theme.of(context).textSecondary),
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: V2Theme.of(context).textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchFooter(L10n l10n) {
    // 当前标签已加载到末尾：不显示「搜索更多」
    if (_currentEndReached && !_isLoading) {
      return SizedBox.shrink();
    }
    final searchedUntil = _searchedUntil;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (searchedUntil != null)
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.chatSearchedUntil(
                    searchedUntil.localizedTime(context),
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: V2Theme.of(context).textSecondary,
                  ),
                ),
              ),
            GestureDetector(
              onTap: _isLoading ? null : _startSearch,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: V2Theme.of(context).cardBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: V2Theme.of(context).divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLoading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(V2Theme.of(context).accent),
                        ),
                      )
                    else
                      Icon(
                        Icons.arrow_downward_outlined,
                        size: 18,
                        color: V2Theme.of(context).accent,
                      ),
                    SizedBox(width: 8),
                    Text(
                      l10n.searchMore,
                      style: TextStyle(
                        fontSize: 14,
                        color: V2Theme.of(context).accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
