import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/image_viewer/image_viewer_v2.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/file_message_manager.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

/// V2 媒体与文件页（仿 Telegram 风格）
///
/// 入口：私聊/群聊设置 → 媒体与文件
/// 两个标签页：
/// - 媒体：图片 + 视频，按月份分组的三方格缩略图网格，点击进入预览
/// - 文件：所有非媒体附件，列表形式（类型图标 + 文件名 + 大小 + 日期），点击打开/下载
class ChatMediaFilesV2 extends StatefulWidget {
  final String roomId;

  const ChatMediaFilesV2({super.key, required this.roomId});

  @override
  State<ChatMediaFilesV2> createState() => _ChatMediaFilesV2State();
}

class _ChatMediaFilesV2State extends State<ChatMediaFilesV2>
    with SingleTickerProviderStateMixin {
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  late final TabController _tabController;

  // 媒体（图片+视频）
  final List<Event> _mediaEvents = [];
  String? _mediaNextBatch;
  bool _mediaEndReached = false;
  bool _mediaLoading = false;
  final ScrollController _mediaScrollController = ScrollController();

  // 文件
  final List<Event> _fileEvents = [];
  String? _fileNextBatch;
  bool _fileEndReached = false;
  bool _fileLoading = false;
  final ScrollController _fileScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _mediaScrollController.addListener(() {
      if (_mediaScrollController.position.pixels >=
          _mediaScrollController.position.maxScrollExtent - 200) {
        _loadMedia();
      }
    });
    _fileScrollController.addListener(() {
      if (_fileScrollController.position.pixels >=
          _fileScrollController.position.maxScrollExtent - 200) {
        _loadFiles();
      }
    });

    // 两个标签都预加载，避免切换时出现空白/加载闪烁
    _loadMedia();
    _loadFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mediaScrollController.dispose();
    _fileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    if (_mediaLoading || _mediaEndReached) return;
    final room = this.room;
    if (room == null) return;
    setState(() => _mediaLoading = true);
    try {
      final result = await room.searchEvents(
        searchFunc: (event) => {
          MessageTypes.Image,
          if (PlatformInfos.supportsVideoPlayer) MessageTypes.Video,
        }.contains(event.messageType),
        nextBatch: _mediaNextBatch,
      );
      if (!mounted) return;
      setState(() {
        _mediaEvents.addAll(result.events);
        _mediaNextBatch = result.nextBatch;
        _mediaEndReached = result.nextBatch == null;
      });
    } catch (e) {
      debugPrint('[MediaFiles] load media failed: $e');
    } finally {
      if (mounted) setState(() => _mediaLoading = false);
    }
  }

  Future<void> _loadFiles() async {
    if (_fileLoading || _fileEndReached) return;
    final room = this.room;
    if (room == null) return;
    setState(() => _fileLoading = true);
    try {
      final result = await room.searchEvents(
        searchFunc: (event) =>
            event.messageType == MessageTypes.File ||
            (event.messageType == MessageTypes.Audio &&
                !event.content.containsKey('org.matrix.msc3245.voice')),
        nextBatch: _fileNextBatch,
      );
      if (!mounted) return;
      setState(() {
        _fileEvents.addAll(result.events);
        _fileNextBatch = result.nextBatch;
        _fileEndReached = result.nextBatch == null;
      });
    } catch (e) {
      debugPrint('[MediaFiles] load files failed: $e');
    } finally {
      if (mounted) setState(() => _fileLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = this.room;

    if (room == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(l10n.youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            V2AppBar(
              title: l10n.mediaAndFiles,
              backgroundColor: V2Theme.of(context).scaffoldBackground,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/v2/rooms');
                }
              },
            ),
            // 标签栏（仿 iOS 分段控件样式）
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
                        _buildSegmentTab(l10n.media, 0),
                        _buildSegmentTab(l10n.files, 1),
                      ],
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  return IndexedStack(
                    index: _tabController.index, // ✅ 直接使用 TabController 的索引，确保绝对同步
                    children: [
                      _buildMediaTab(l10n),
                      _buildFilesTab(l10n),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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

  // ===================== 媒体标签 =====================

  Widget _buildMediaTab(L10n l10n) {
    if (_mediaEvents.isEmpty && !_mediaLoading) {
      return _buildEmpty(
        icon: Icons.photo_library_outlined,
        text: l10n.noMedia,
      );
    }

    // 按月份分组
    final eventsByMonth = <DateTime, List<Event>>{};
    for (final event in _mediaEvents) {
      final month = DateTime(
        event.originServerTs.year,
        event.originServerTs.month,
      );
      eventsByMonth[month] ??= [];
      eventsByMonth[month]!.add(event);
    }
    final monthEntries = eventsByMonth.entries.toList();

    return ListView.builder(
      controller: _mediaScrollController,
      padding: EdgeInsets.only(bottom: 24),
      itemCount: monthEntries.length + 1,
      itemBuilder: (context, i) {
        if (i == monthEntries.length) {
          return _buildLoadMoreIndicator(
            loading: _mediaLoading,
            endReached: _mediaEndReached,
          );
        }
        final month = monthEntries[i].key;
        final events = monthEntries[i].value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                DateFormat.yMMMM(
                  safeDateFormatLocale(context),
                ).format(month),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: V2Theme.of(context).textSecondary,
                ),
              ),
            ),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              padding: EdgeInsets.symmetric(horizontal: 2),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return MediaThumbnail(event: event);
              },
            ),
          ],
        );
      },
    );
  }

  // ===================== 文件标签 =====================

  Widget _buildFilesTab(L10n l10n) {
    if (_fileEvents.isEmpty && !_fileLoading) {
      return _buildEmpty(
        icon: Icons.folder_outlined,
        text: l10n.noFiles,
      );
    }

    return ListView.separated(
      controller: _fileScrollController,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _fileEvents.length + 1,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: V2Theme.of(context).divider,
        indent: 62,
      ),
      itemBuilder: (context, i) {
        if (i == _fileEvents.length) {
          return _buildLoadMoreIndicator(
            loading: _fileLoading,
            endReached: _fileEndReached,
          );
        }
        return FileTile(event: _fileEvents[i]);
      },
    );
  }

  // ===================== 通用组件 =====================

  Widget _buildEmpty({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: V2Theme.of(context).textSecondary,
          ),
          SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreIndicator({
    required bool loading,
    required bool endReached,
  }) {
    if (loading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: V2Theme.of(context).accent,
            ),
          ),
        ),
      );
    }
    return SizedBox(height: 16);
  }
}

/// 媒体缩略图（图片/视频），点击进入预览
class MediaThumbnail extends StatelessWidget {
  final Event event;

  const MediaThumbnail({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final isVideo = event.messageType == MessageTypes.Video;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ImageViewerV2(
            event,
            outerContext: context,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MxcImage(
            event: event,
            fit: BoxFit.cover,
            animated: true,
            isThumbnail: true,
            placeholder: (_) => Container(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Color(0xFF2C2C2E)
                  : Color(0xFFEEEEEE),
            ),
          ),
          if (isVideo)
            Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 36,
                shadows: [BoxShadow(color: Colors.black45, blurRadius: 4)],
              ),
            ),
        ],
      ),
    );
  }
}

/// 文件列表项（仿 Telegram：彩色类型图标 + 文件名 + 大小/日期）
class FileTile extends StatefulWidget {
  final Event event;

  const FileTile({super.key, required this.event});

  @override
  State<FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<FileTile> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.event.content;
    final fileName =
        content.tryGet<String>('filename') ??
        content.tryGet<String>('body') ??
        L10n.of(context).unknownFile;
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'FILE';
    final typeColor = _getTypeColor(extension);
    final fileSize = widget.event.sizeString ?? '';
    final locale = safeDateFormatLocale(context);
    final dateStr = DateFormat('yyyy/MM/dd', locale).format(
      widget.event.originServerTs,
    );

    return InkWell(
      onTap: _opening ? null : _openFile,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // 彩色文件图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  extension.length > 4
                      ? extension.substring(0, 4)
                      : extension,
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            // 文件名 + 大小/日期
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    [fileSize, dateStr].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: V2Theme.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (_opening)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: V2Theme.of(context).accent,
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                color: V2Theme.of(context).textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile() async {
    final l10n = L10n.of(context);
    setState(() => _opening = true);
    try {
      if (await FileMessageManager.isCached(widget.event)) {
        final path = await FileMessageManager.download(widget.event);
        await FileMessageManager.open(path);
      } else {
        V2Toast.show(l10n.downloadingFile);
        final path = await FileMessageManager.download(widget.event);
        if (mounted) await FileMessageManager.open(path);
      }
    } catch (e) {
      debugPrint('[MediaFiles] open file failed: $e');
      if (mounted) {
        V2Toast.show(l10n.couldNotOpenFile);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Color _getTypeColor(String ext) {
    switch (ext) {
      case 'XLS':
      case 'XLSX':
      case 'CSV':
        return Color(0xFF217346);
      case 'DOC':
      case 'DOCX':
        return Color(0xFF2B579A);
      case 'PDF':
        return Color(0xFFE53935);
      case 'ZIP':
      case 'RAR':
      case '7Z':
        return Color(0xFFFF9800);
      case 'PPT':
      case 'PPTX':
        return Color(0xFFE64A19);
      case 'TXT':
        return Color(0xFF607D8B);
      case 'PNG':
      case 'JPG':
      case 'JPEG':
      case 'GIF':
      case 'WEBP':
        return Color(0xFF8E24AA);
      default:
        return V2Theme.of(context).accent;
    }
  }
}
