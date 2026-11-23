import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/invitation_selection/invitation_selection.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/settings_emotes/settings_emotes.dart';
import 'package:fluffychat/pages_v2/bootstrap_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_details_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_group_edit_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_media_files_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_members_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_privacy_security_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_search_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/chat_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/create_group_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/key_verification_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/pinned_messages_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/poll_list_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/room_permissions_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/room_role_members_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/room_roles_permissions_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/set_remark_v2.dart';
import 'package:fluffychat/pages_v2/chat_v2/user_profile_v2.dart';
import 'package:fluffychat/pages_v2/home_v2.dart';
import 'package:fluffychat/pages_v2/intro_v2.dart';
import 'package:fluffychat/pages_v2/invite_friends_v2.dart';
import 'package:fluffychat/pages_v2/join_room_preview_v2.dart';
import 'package:fluffychat/pages_v2/login_v2.dart';
import 'package:fluffychat/pages_v2/public_groups_v2/public_group_list_v2.dart';
import 'package:fluffychat/pages_v2/public_groups_v2/public_groups_v2.dart';
import 'package:fluffychat/pages_v2/qr_scanner_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/about_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/app_lock_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/appearance_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/bind_email_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/blocked_users_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/change_email_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/devices_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/edit_profile_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/edit_username_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/email_detail_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/encryption_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/language_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/notification_chat_mode_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/notification_room_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/notifications_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/privacy_security_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/settings_password_v2.dart';
import 'package:fluffychat/pages_v2/settings_v2/wallet_detail_v2.dart';
import 'package:fluffychat/pages_v2/sign_in_v2.dart';
import 'package:fluffychat/widgets/config_viewer.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/log_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

abstract class AppRoutes {
  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? '/v2/rooms'
      : null;

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? null
      : '/home';

  AppRoutes();

  static final List<RouteBase> routes = [
    GoRoute(
      path: '/',
      redirect: (context, state) =>
          Matrix.of(context).widget.clients.any((client) => client.isLogged())
          ? '/v2/rooms'
          : '/home',
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const IntroV2()),
      redirect: loggedInRedirect,
      routes: [
        GoRoute(
          path: 'sign_in',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInV2(signUp: false)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'sign_up',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, SignInV2(signUp: true)),
          redirect: loggedInRedirect,
        ),
        GoRoute(
          path: 'login',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            LoginV2(client: state.extra as Client),
          ),
          redirect: loggedInRedirect,
        ),
      ],
    ),
    GoRoute(
      path: '/logs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const LogViewer()),
    ),
    GoRoute(
      path: '/configs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const ConfigViewer()),
    ),
    GoRoute(
      path: '/backup',
      redirect: loggedOutRedirect,
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        BootstrapV2(reset: state.uri.queryParameters['reset'] == 'true'),
      ),
    ),
    // V2 自适应主框架（ShellRoute）：
    // 宽屏 → 左侧导航栏+列表（HomeV2），右侧详情；窄屏 → 单页切换
    // 注意：宽度判断放在 _AdaptiveShell 组件内（build 时读取 MediaQuery），
    // 这样浏览器窗口缩放时布局能实时自适应，而不是只在导航时判断一次。
    ShellRoute(
      pageBuilder: (context, state, child) => noTransitionPageBuilder(
        context,
        state,
        _AdaptiveShell(child: child),
      ),
      routes: [
        // V2 主页（4 Tab）：宽屏右侧留空（EmptyPage），窄屏显示 HomeV2
        GoRoute(
          path: '/v2/rooms',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const _RoomsEntry(),
          ),
        ),
        // V2 聊天页（宽屏显示在右侧面板）
        GoRoute(
          path: '/v2/rooms/chat/:roomId',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            ChatV2(
              roomId: state.pathParameters['roomId']!,
              shareItems: state.extra is List<ShareItem>
                  ? state.extra as List<ShareItem>
                  : null,
              eventId: state.uri.queryParameters['event'],
              action: state.uri.queryParameters['action'],
            ),
          ),
          redirect: loggedOutRedirect,
          routes: [
            // V2 聊天内搜索页
            GoRoute(
              path: 'search',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                ChatSearchV2(roomId: state.pathParameters['roomId']!),
              ),
              redirect: loggedOutRedirect,
            ),
            // V2 聊天详情
            GoRoute(
              path: 'details',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                ChatDetailsV2(roomId: state.pathParameters['roomId']!),
              ),
              redirect: loggedOutRedirect,
              routes: [
                GoRoute(
                  path: 'edit',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatGroupEditV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'access',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatPrivacySecurityV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'pinned',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    PinnedMessagesV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'media',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatMediaFilesV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'polls',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    PollListV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'profile',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    UserProfileV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'verify',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    KeyVerificationV2(
                      roomId: state.pathParameters['roomId'],
                      existingRequest: state.extra as KeyVerification?,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'remark',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    SetRemarkV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'members',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatMembersV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'permissions',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    RoomPermissionsV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'roles',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    RoomRolesPermissionsV2(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'roles/admin',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    RoomRoleMembersV2(
                      roomId: state.pathParameters['roomId']!,
                      role: PowerLevelRole.admin,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'roles/moderator',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    RoomRoleMembersV2(
                      roomId: state.pathParameters['roomId']!,
                      role: PowerLevelRole.moderator,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'invite',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    InvitationSelection(
                      roomId: state.pathParameters['roomId']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'emotes',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    EmotesSettings(roomId: state.pathParameters['roomId']),
                  ),
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
          ],
        ),
        // V2 加入聊天室预览页
        GoRoute(
          path: '/v2/join-room/:address',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            JoinRoomPreviewV2(address: Uri.decodeComponent(state.pathParameters['address']!)),
          ),
        ),
        // V2 邀请朋友页
        GoRoute(
          path: '/v2/invite-friends',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const InviteFriendsV2(),
          ),
        ),
        // 接收方：对端发起的验证请求（不依赖当前房间）
        GoRoute(
          path: '/v2/verify',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            KeyVerificationV2(
              existingRequest: state.extra as KeyVerification?,
            ),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 新建群聊页
        GoRoute(
          path: '/v2/create-group',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const CreateGroupV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 公群分类列表页（占位空列表，后续从服务器拉取数据）
        GoRoute(
          path: '/v2/public-groups/:type',
          pageBuilder: (context, state) {
            final typeName = state.pathParameters['type'] ?? '';
            final type = PublicGroupType.values.firstWhere(
              (e) => e.name == typeName,
              orElse: () => PublicGroupType.tech,
            );
            return defaultPageBuilder(
              context,
              state,
              PublicGroupListV2(type: type),
            );
          },
          redirect: loggedOutRedirect,
        ),
        // V2 编辑个人资料页
        GoRoute(
          path: '/v2/edit-profile',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const EditProfileV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 绑定邮箱页
        GoRoute(
          path: '/v2/bind-email',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const BindEmailV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 邮箱详情页（已绑定，可修改邮箱）
        GoRoute(
          path: '/v2/email-detail',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const EmailDetailV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 修改邮箱页
        GoRoute(
          path: '/v2/change-email',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const ChangeEmailV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 钱包地址详情页
        GoRoute(
          path: '/v2/wallet-detail',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const WalletDetailV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 用户名编辑页
        GoRoute(
          path: '/v2/edit-username',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const EditUsernameV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 外观设置页
        GoRoute(
          path: '/v2/appearance',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const AppearanceV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 通知设置页
        GoRoute(
          path: '/v2/notifications',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const NotificationsV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 通知 - 群聊通知模式
        GoRoute(
          path: '/v2/notifications/group',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const NotificationChatModeV2(type: NotificationChatType.group),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 通知 - 私聊通知模式
        GoRoute(
          path: '/v2/notifications/private',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const NotificationChatModeV2(type: NotificationChatType.private),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 通知 - 单个群聊独立设置
        GoRoute(
          path: '/v2/notifications/room/:roomId',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            NotificationRoomV2(roomId: state.pathParameters['roomId']!),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 隐私与安全页
        GoRoute(
          path: '/v2/privacy-security',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const PrivacySecurityV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 已屏蔽用户列表页
        GoRoute(
          path: '/v2/blocked-users',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const BlockedUsersV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 登录密码修改页
        GoRoute(
          path: '/v2/settings/password',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const SettingsPasswordV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 密码锁设置页
        GoRoute(
          path: '/v2/settings/app-lock',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const AppLockV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 加密与恢复密钥页
        GoRoute(
          path: '/v2/settings/encryption',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const EncryptionV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 设备管理页
        GoRoute(
          path: '/v2/devices',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const DevicesV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 关于页
        GoRoute(
          path: '/v2/about',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const AboutV2(),
          ),
          redirect: loggedOutRedirect,
        ),
        // V2 语言设置页
        GoRoute(
          path: '/v2/settings/language',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            const LanguageV2(),
          ),
          redirect: loggedOutRedirect,
        ),
      ],
    ),
    // V2 全屏扫码页（相机取景，保持全屏）
    GoRoute(
      path: '/v2/scan-qr',
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        QrScannerV2(onScan: (data) => context.pop(data)),
      ),
    ),
    // V2 新建私聊页（联系人页「创建新聊天」/ matrix.to 深链入口）
    GoRoute(
      path: '/v2/new-private-chat',
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        NewPrivateChat(deeplink: state.uri.fragment),
      ),
      redirect: loggedOutRedirect,
    ),
  ];

  static Page noTransitionPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) => NoTransitionPage(
    key: state.pageKey,
    restorationId: state.pageKey.value,
    child: child,
  );

  static Page defaultPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) {
    final clientName = state.uri.queryParameters['client'];
    if (clientName != null) {
      final matrix = Matrix.of(context);
      final client = matrix.getClientByName(clientName);
      if (client != null) matrix.setActiveClient(client);
    }
    return FluffyThemes.isColumnMode(context)
        ? noTransitionPageBuilder(context, state, child)
        : MaterialPage(
            key: state.pageKey,
            restorationId: state.pageKey.value,
            child: child,
          );
  }
}

/// 自适应主框架：在 build 阶段通过 MediaQuery 判断宽度，
/// 从而在浏览器窗口缩放时实时切换「左右双栏」与「单栏」布局。
class _AdaptiveShell extends StatelessWidget {
  final Widget child;

  const _AdaptiveShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final isWide = FluffyThemes.isColumnMode(context);
    if (!isWide) return child;
    return Row(
      children: [
        SizedBox(
          width: FluffyThemes.columnWidth,
          child: const HomeV2(),
        ),
        Container(width: 1, color: Theme.of(context).dividerColor),
        Expanded(child: child),
      ],
    );
  }
}

/// /v2/rooms 入口：宽屏返回 EmptyPage（右侧留空，HomeV2 由 Shell 提供），
/// 窄屏返回 HomeV2（全屏）。宽度判断同样在 build 阶段，跟随窗口缩放。
class _RoomsEntry extends StatelessWidget {
  const _RoomsEntry();

  @override
  Widget build(BuildContext context) {
    return FluffyThemes.isColumnMode(context)
        ? const EmptyPage()
        : const HomeV2();
  }
}
