import 'dart:async';

import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// V2 全局搜索 mixin（公开房间目录 + 用户目录 + 本地房间过滤）
///
/// 由会话列表、联系人等页面复用，避免重复实现搜索逻辑。
mixin V2SearchMixin<T extends StatefulWidget> on State<T> {
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  bool isSearchMode = false;
  bool isSearching = false;
  QueryPublicRoomsResponse? roomSearchResult;
  SearchUserDirectoryResponse? userSearchResult;

  Timer? _coolDown;

  /// 搜索框输入：500ms 防抖后请求服务端
  void onSearchEnter(String text) {
    if (text.trim().isEmpty) {
      // 清空文本时仍停留在搜索页（仿微信），只清空服务端结果。
      // 输入框不卸载，避免焦点丢失导致要再点一次。
      _coolDown?.cancel();
      setState(() {
        isSearching = false;
        roomSearchResult = null;
        userSearchResult = null;
      });
      return;
    }
    if (!isSearchMode) {
      setState(() => isSearchMode = true);
    }
    _coolDown?.cancel();
    _coolDown = Timer(const Duration(milliseconds: 500), _search);
  }

  /// 点击搜索框进入搜索模式
  void startSearch() {
    setState(() => isSearchMode = true);
    _coolDown?.cancel();
    // 搜索模式的输入框要等本帧重建后才挂载，下一帧再请求焦点，
    // 否则焦点会因旧输入框卸载而丢失，导致要点两次才能输入。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isSearchMode) searchFocusNode.requestFocus();
    });
    if (searchController.text.trim().isNotEmpty) {
      _coolDown = Timer(const Duration(milliseconds: 500), _search);
    }
  }

  /// 退出搜索
  void cancelSearch({bool unfocus = true}) {
    _coolDown?.cancel();
    setState(() {
      searchController.clear();
      isSearchMode = false;
      isSearching = false;
      roomSearchResult = null;
      userSearchResult = null;
    });
    if (unfocus) searchFocusNode.unfocus();
  }

  /// 真正执行服务端搜索：公开房间目录 + 用户目录
  Future<void> _search() async {
    final client = Matrix.of(context).client;
    final searchQuery = searchController.text.trim();
    if (searchQuery.isEmpty || !isSearchMode) return;

    if (!isSearching) setState(() => isSearching = true);

    QueryPublicRoomsResponse? roomResult;
    SearchUserDirectoryResponse? userResult;
    try {
      roomResult = await client.queryPublicRooms(
        filter: PublicRoomQueryFilter(genericSearchTerm: searchQuery),
        limit: 20,
      );

      // 输入是合法 # 别名但目录没查到时，用别名直接反查 roomId
      if (searchQuery.isValidMatrixIdStrict() &&
          searchQuery.sigil == '#' &&
          !roomResult.chunk.any((room) => room.canonicalAlias == searchQuery)) {
        final response = await client.getRoomIdByAlias(searchQuery);
        final roomId = response.roomId;
        if (roomId != null) {
          roomResult.chunk.add(
            PublishedRoomsChunk(
              name: searchQuery,
              guestCanJoin: false,
              numJoinedMembers: 0,
              roomId: roomId,
              worldReadable: false,
              canonicalAlias: searchQuery,
            ),
          );
        }
      }

      userResult = await client.searchUserDirectory(searchQuery, limit: 20);
    } catch (e, s) {
      Logs().w('Searching has crashed', e, s);
      if (!mounted) return;
      V2Toast.show(e.toLocalizedString(context));
    }

    if (!isSearchMode || !mounted) return;
    setState(() {
      isSearching = false;
      roomSearchResult = roomResult;
      userSearchResult = userResult;
    });
  }

  /// 点击公开房间 → 跳转加入房间预览页
  void onPublicRoomTap(PublishedRoomsChunk chunk) {
    final address = chunk.canonicalAlias?.toString() ?? chunk.roomId;
    context.push('/v2/join-room/${Uri.encodeComponent(address)}');
  }

  /// 释放搜索相关资源（在 dispose 中调用）
  void disposeSearch() {
    _coolDown?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
  }
}
