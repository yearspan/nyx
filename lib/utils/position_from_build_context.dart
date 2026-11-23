import 'package:flutter/widgets.dart';

extension PositionFromBuildContext on BuildContext {
  RelativeRect get position {
    final overlay = Overlay.of(this).context.findRenderObject() as RenderBox;

    final button = findRenderObject() as RenderBox;

    return RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(const Offset(0, -65), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + const Offset(-50, 0),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
  }
}
