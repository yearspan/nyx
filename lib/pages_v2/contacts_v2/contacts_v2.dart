import 'dart:async';

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/pages_v2/chat_v2/user_profile_v2.dart';
import 'package:fluffychat/pages_v2/contacts_v2/contacts_v2_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/search/v2_search_mixin.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:matrix/matrix.dart';

/// V2 联系人页（Page）
class ContactsV2 extends StatefulWidget {
  const ContactsV2({super.key});

  @override
  ContactsV2Controller createState() => ContactsV2Controller();
}

class ContactsV2Controller extends State<ContactsV2>
    with TickerProviderStateMixin, V2SearchMixin {
  final ScrollController scrollController = ScrollController();
  bool showBanner = true;

  /// 联系人页「加入群聊」Banner 是否隐藏的本地存储 key
  static const String _bannerHiddenKey = 'v2_contacts_banner_hidden';

  /// 每个字母分组的 GlobalKey，用于跳转
  final Map<String, GlobalKey> sectionKeys = {};

  StreamSubscription? _onSyncUpdate;

  @override
  void initState() {
    super.initState();
    // 读取 Banner 隐藏状态，重启后保持隐藏
    final hidden = Matrix.of(context).store.getBool(_bannerHiddenKey) ?? false;
    showBanner = !hidden;
    _onSyncUpdate = Matrix.of(context).client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _onSyncUpdate?.cancel();
    disposeSearch();
    scrollController.dispose();
    super.dispose();
  }

  /// 获取群聊列表（非 DM、非 Space、已加入）
  List<Room> get groupRooms => Matrix.of(context).client.rooms
      .where((r) => !r.isSpace && !r.isDirectChat && r.membership == Membership.join)
      .toList();

  /// 获取联系人列表（DM 的对方）
  List<Room> get contactRooms => Matrix.of(context).client.rooms
      .where((r) => !r.isSpace && r.isDirectChat && r.membership == Membership.join)
      .toList();

  /// 联系人按首字母分组排序（中文取拼音首字母）
  Map<String, List<Room>> get groupedContacts {
    final contacts = contactRooms;
    final map = <String, List<Room>>{};
    for (final room in contacts) {
      final name = room.getLocalizedDisplayname().trim();
      final key = _firstLetter(name);
      map.putIfAbsent(key, () => []).add(room);
    }
    // 每个分组内按完整拼音排序，使中文也按字母顺序排列
    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final pa = PinyinHelper.getPinyin(a.getLocalizedDisplayname());
        final pb = PinyinHelper.getPinyin(b.getLocalizedDisplayname());
        return pa.compareTo(pb);
      });
    }
    // 按字母排序，# 排最后
    final sortedKeys = map.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return {for (final k in sortedKeys) k: map[k]!};
  }

  /// 根据名称取分组首字母
  /// - A-Z 开头：直接用该字母
  /// - 中文开头：取拼音首字母
  /// - 其他（数字、符号等）：归入 #
  static String _firstLetter(String name) {
    if (name.isEmpty) return '#';
    final first = name[0];
    final upper = first.toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(upper)) return upper;
    final pinyin = PinyinHelper.getShortPinyin(first);
    if (pinyin.isNotEmpty) {
      final pl = pinyin[0].toUpperCase();
      if (RegExp(r'[A-Z]').hasMatch(pl)) return pl;
    }
    return '#';
  }

  /// 所有可能的字母（A-Z + #），用于索引栏
  List<String> get alphabetKeys {
    final grouped = groupedContacts;
    final keys = <String>[];
    for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
      final letter = String.fromCharCode(c);
      if (grouped.containsKey(letter)) {
        keys.add(letter);
      }
    }
    if (grouped.containsKey('#')) {
      keys.add('#');
    }
    return keys;
  }

  /// 点击字母 → 滚动到对应分组
  void scrollToLetter(String letter) {
    final key = sectionKeys[letter];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  /// 关闭 Banner
  Future<void> closeBanner() async {
    setState(() {
      showBanner = false;
    });
    await Matrix.of(context).store.setBool(_bannerHiddenKey, true);
  }

  /// 创建群聊
  void createGroup() {
    context.push('/v2/create-group');
  }

  /// 创建新聊天（跳转到新私聊页）
  void createChat() {
    context.push('/v2/new-private-chat');
  }
  void inviteFriend() {
    context.push('/v2/invite-friends');
  }

  /// 点击联系人 → 打开 DM 房间
  void openContact(Room room) {
    context.push('/v2/rooms/chat/${room.id}');
  }

  /// 点击群聊 → 打开群聊
  void openGroup(Room room) {
    context.push('/v2/rooms/chat/${room.id}');
  }

  /// 点击搜索到的用户 → 打开其 V2 个人资料页
  void onUserTap(Profile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileV2(userId: profile.userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ContactsV2View(this);
}
