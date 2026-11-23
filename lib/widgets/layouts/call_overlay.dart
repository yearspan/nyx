import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages_v2/chat_v2/call/call_page_v2.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

class CallOverlay extends StatefulWidget {
  final Widget child;
  const CallOverlay({required this.child, super.key});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  /// 迷你悬浮窗左上角相对屏幕的偏移
  Offset _miniOffset = Offset.zero;

  /// 是否已根据屏幕尺寸初始化过位置
  bool _positionInitialized = false;

  static const double _miniWidth = 108;
  static const double _miniHeight = 156;
  static const double _edgePadding = 8;

  /// 首次进入时把迷你窗放到右侧垂直居中；屏幕尺寸变化时把位置夹回可视区域
  void _ensurePosition(Size size) {
    if (!_positionInitialized) {
      _miniOffset = Offset(
        size.width - _miniWidth - _edgePadding,
        (size.height - _miniHeight) / 2,
      );
      _positionInitialized = true;
    } else {
      _miniOffset = Offset(
        _miniOffset.dx.clamp(0.0, size.width - _miniWidth),
        _miniOffset.dy.clamp(0.0, size.height - _miniHeight),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: Matrix.of(context).activeCallRoomId,
      builder: (context, roomId, _) {
        if (roomId == null) return widget.child;
        return ValueListenableBuilder<CallPosition>(
          valueListenable: Matrix.of(context).callPosition,
          builder: (context, callPosition, _) {
            final callFullScreen = callPosition == CallPosition.fullScreen;
            return LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                _ensurePosition(size);
                return Stack(
                  children: [
                    widget.child,
                    Positioned(
                      left: callFullScreen ? 0 : _miniOffset.dx,
                      top: callFullScreen ? 0 : _miniOffset.dy,
                      right: callFullScreen ? 0 : null,
                      bottom: callFullScreen ? 0 : null,
                      width: callFullScreen ? null : _miniWidth,
                      height: callFullScreen ? null : _miniHeight,
                      // 统一用 GestureDetector 包裹，保持 fullscreen/mini
                      // 下 widget 树结构一致，避免 CallPageV2 的 State
                      // （含正在通话的 CallViewModel）在切换时被销毁重建。
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: callFullScreen
                            ? null
                            : (details) {
                                setState(() {
                                  _miniOffset = Offset(
                                    (_miniOffset.dx + details.delta.dx).clamp(
                                      0.0,
                                      size.width - _miniWidth,
                                    ),
                                    (_miniOffset.dy + details.delta.dy).clamp(
                                      0.0,
                                      size.height - _miniHeight,
                                    ),
                                  );
                                });
                              },
                        onPanEnd: callFullScreen
                            ? null
                            : (_) {
                                final centerX =
                                    _miniOffset.dx + _miniWidth / 2;
                                final targetX = centerX < size.width / 2
                                    ? _edgePadding
                                    : size.width - _miniWidth - _edgePadding;
                                setState(() {
                                  _miniOffset = Offset(
                                    targetX,
                                    _miniOffset.dy,
                                  );
                                });
                              },
                        child: _buildCallSurface(roomId, callFullScreen),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCallSurface(String roomId, bool fullScreen) {
    return Material(
      elevation: fullScreen ? 0 : 4,
      clipBehavior: Clip.hardEdge,
      shape: fullScreen
          ? null
          : RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey),
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
      child: Navigator(
        onDidRemovePage: (_) {
          Matrix.of(context).activeCallRoomId.value = null;
        },
        pages: [
          MaterialPage(child: CallPageV2(roomId: roomId)),
        ],
      ),
    );
  }
}
