import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages_v2/contacts_v2/contacts_v2.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/search/v2_search_results.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fluffychat/widgets_v2/v2_search_bar.dart';
import 'package:matrix/matrix.dart';

/// V2 联系人视图（View）
class ContactsV2View extends StatelessWidget {
  final ContactsV2Controller controller;
  const ContactsV2View(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // 搜索模式：显示搜索结果页
    if (controller.isSearchMode) {
      return Column(
        children: [
          V2AppBar(
            title: l10n.search,
            showBack: true,
            onBack: controller.cancelSearch,
          ),
          V2SearchBar(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            hintText: l10n.search,
            onChanged: controller.onSearchEnter,
            onSubmitted: () =>
                controller.onSearchEnter(controller.searchController.text),
          ),
          Expanded(child: _SearchResults(controller: controller)),
        ],
      );
    }

    final groups = controller.groupRooms;
    final groupedContacts = controller.groupedContacts;
    final alphabetKeys = controller.alphabetKeys;

    return Column(
      children: [
        // 顶部 AppBar
        V2AppBar(
          title: l10n.contacts,
          showBack: false,
        ),

        // 搜索框：点击进入搜索模式
        GestureDetector(
          onTap: controller.startSearch,
          child: AbsorbPointer(
            child: V2SearchBar(
              controller: controller.searchController,
              focusNode: controller.searchFocusNode,
              hintText: l10n.search,
            ),
          ),
        ),

        Expanded(
          child: Stack(
            children: [
              // 主列表
              ListView(
                padding: EdgeInsets.only(left: 16, right: 32),
                children: [
                  // 顶部 Banner
                  // if (controller.showBanner)
                  //   _BannerCard(
                  //     onClose: controller.closeBanner,
                  //     onCreateGroup: controller.createGroup,
                  //   ),

                  // 群聊区域
                  _SectionHeader(
                    icon: Icons.group_add_outlined,
                    title: l10n.groupChats,
                    actionLabel: l10n.createGroupChat,
                  ),
                  InkWell(
                    onTap: controller.createGroup,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Image.asset("assets/images/chat/create_group.png",width: 26, color: V2Theme.accent,),
                          SizedBox(width: 8),
                          Text(
                            l10n.createGroupChat,
                            style: TextStyle(
                              fontSize: 16,
                              color: V2Theme.of(context).accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 群聊列表
                  ...groups.map((room) => _ContactTile(
                    room: room,
                    isGroup: true,
                    onTap: () => controller.openGroup(room),
                  )),

                  SizedBox(height: 16),

                  // 联系人区域
                  _SectionHeader(
                    icon: Icons.person_add_outlined,
                    title: l10n.contacts,
                    actionLabel: l10n.inviteFriends,
                  ),
                  InkWell(
                    onTap: controller.inviteFriend,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Image.asset("assets/images/chat/add_member.png",width: 26,color: V2Theme.accent),
                          SizedBox(width: 8),
                          Text(
                            l10n.inviteFriends,
                            style: TextStyle(
                              fontSize: 16,
                              color: V2Theme.of(context).accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 联系人按字母分组
                  ...groupedContacts.entries.expand((entry) {
                    final letter = entry.key;
                    final rooms = entry.value;
                    // 为每个字母创建 GlobalKey
                    controller.sectionKeys.putIfAbsent(
                      letter,
                      () => GlobalKey(),
                    );
                    return [
                      _LetterHeader(
                        key: controller.sectionKeys[letter],
                        letter: letter,
                      ),
                      ...rooms.map((room) => _ContactTile(
                        room: room,
                        isGroup: false,
                        onTap: () => controller.openContact(room),
                      )),
                    ];
                  }),

                  SizedBox(height: 80),
                ],
              ),

              // 右侧字母索引栏
              if (alphabetKeys.isNotEmpty)
                Positioned(
                  right: 2,
                  top: 0,
                  bottom: 0,
                  child: _AlphabetBar(
                    keys: alphabetKeys,
                    onTap: controller.scrollToLetter,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部提示 Banner
class _BannerCard extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onCreateGroup;

  const _BannerCard({required this.onClose, required this.onCreateGroup});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: V2Theme.of(context).accent.withOpacity(0.3),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.joinGroupBannerTitle,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Icon(Icons.close, color: V2Theme.of(context).textSecondary, size: 20),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            l10n.joinGroupBannerDesc,
            style: TextStyle(fontSize: 13, color: V2Theme.of(context).textSecondary),
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCreateGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: V2Theme.of(context).accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                padding: EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(l10n.createGroupChat, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 区域标题
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String actionLabel;

  const _SectionHeader({required this.icon, required this.title, required this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          // Icon(icon, size: 18, color: V2Theme.of(context).textSecondary),
          // SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: V2Theme.of(context).textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Spacer(),
          // Text(
          //   actionLabel,
          //   style: TextStyle(
          //     fontSize: 13,
          //     color: V2Theme.of(context).accent,
          //   ),
          // ),
        ],
      ),
    );
  }
}

/// 群聊/联系人 列表项
class _ContactTile extends StatelessWidget {
  final Room room;
  final bool isGroup;
  final VoidCallback onTap;

  const _ContactTile({required this.room, required this.isGroup, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayName = room.getLocalizedDisplayname();
    final subtitle = isGroup
        ? l10n.membersCount(room.summary.mJoinedMemberCount ?? 0)
        : (room.lastEvent != null ? l10n.recentlyOnline : l10n.lastSeenLongAgo);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Avatar(
              mxContent: room.avatar,
              name: displayName,
              size: 48,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: V2Theme.of(context).textSecondary),
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

/// 字母分组头（A, B, C...）
class _LetterHeader extends StatelessWidget {
  final String letter;

  const _LetterHeader({super.key, required this.letter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: V2Theme.of(context).textSecondary,
        ),
      ),
    );
  }
}

/// 右侧字母索引栏
class _AlphabetBar extends StatelessWidget {
  final List<String> keys;
  final void Function(String) onTap;

  const _AlphabetBar({required this.keys, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localY = details.localPosition.dy;
        final itemHeight = box.size.height / keys.length;
        final index = (localY / itemHeight).clamp(0, keys.length - 1).toInt();
        onTap(keys[index]);
      },
      onVerticalDragDown: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localY = details.localPosition.dy;
        final itemHeight = box.size.height / keys.length;
        final index = (localY / itemHeight).clamp(0, keys.length - 1).toInt();
        onTap(keys[index]);
      },
      child: Container(
        width: 24,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: keys
              .map((letter) => GestureDetector(
                    onTap: () => onTap(letter),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: V2Theme.of(context).textSecondary,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

/// 搜索结果列表（复用公共组件 V2SearchResults）
class _SearchResults extends StatelessWidget {
  final ContactsV2Controller controller;
  const _SearchResults({required this.controller});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final keyword = controller.searchController.text.trim().toLowerCase();

    // 本地已加入的群聊 + 联系人按名称过滤
    final localRooms = client.rooms
        .where(
          (r) =>
              !r.isSpace &&
              r.membership != Membership.leave &&
              r.membership != Membership.ban &&
              r.getLocalizedDisplayname().toLowerCase().contains(keyword),
        )
        .toList();

    return V2SearchResults(
      roomSearchResult: controller.roomSearchResult,
      userSearchResult: controller.userSearchResult,
      isSearching: controller.isSearching,
      keyword: keyword,
      localRooms: localRooms,
      localSectionTitle: L10n.of(context).contacts,
      onLocalRoomTap: (room) => room.isDirectChat
          ? controller.openContact(room)
          : controller.openGroup(room),
    );
  }
}

