import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 聊天气泡封装组件
///
/// 用 CustomPaint 绘制带尖角的圆角气泡。
/// 其尖角样式（尾巴）参考 Telegram 设计，位于气泡最底部。
class ChatBubbleItem extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final bool isMe; // true 为右侧发送方，false 为左侧接收方
  final bool showTail; // 是否绘制尾巴，默认 true
  final EdgeInsets? padding; // 可覆盖默认内边距（图片/视频用 EdgeInsets.zero）

  const ChatBubbleItem({
    super.key,
    required this.child,
    required this.backgroundColor,
    required this.isMe,
    this.showTail = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    // 全平台适配：手机取屏宽 75%，平板/桌面封顶 500 避免气泡过宽
    final maxWidth = math.min(
      MediaQuery.of(context).size.width * 0.75,
      500.0,
    );
    return CustomPaint(
      painter: ChatBubblePainter(
        color: backgroundColor,
        isMe: isMe,
        showTail: showTail,
      ),
      child: Container(
        padding: padding ??
            (showTail
                ? EdgeInsets.fromLTRB(
              isMe ? 12 : 16,
              10,
              isMe ? 16 : 12,
              10,
            )
                : EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 自定义气泡路径绘制器 (Telegram 风格)
class ChatBubblePainter extends CustomPainter {
  final Color color;
  final bool isMe;
  final bool showTail;

  const ChatBubblePainter({
    required this.color,
    required this.isMe,
    this.showTail = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true; // 开启抗锯齿

    const rLarge = 16.0; // 主体圆角半径
    const tailHeight = 16.0; // 尾巴区域的高度（从底部向上计算）
    const tailWidth = 20.0; // 尾巴向侧面伸出的最大宽度

    final w = size.width;
    final h = size.height;
    final path = Path();

    if (showTail && isMe) {
      // --- 右侧气泡：尾巴在右下角 ---
      // 1. 从顶部左端开始
      path.moveTo(rLarge, 0);
      // 2. 顶边
      path.lineTo(w - rLarge, 0);
      // 3. 右上圆角
      path.quadraticBezierTo(w, 0, w, rLarge);
      // 4. 右边下部
      path.lineTo(w, h - tailHeight);
      // 5. 关键：绘制 Telegram 风格右下角尖角
      // 路径：顺时针。从右边下部 (w, h-tailHeight) 开始
      // 1) 向下绘制一段弧度，作为尖角上部
      path.cubicTo(
        w, h - (tailHeight * 0.4), // 控制点 1
        w, h - (tailHeight * 0.2), // 控制点 2
        w + (tailWidth * 0.2), h,  // 终点
      );
      // 2) 绘制尖角末梢（带有极小弧度）
      path.quadraticBezierTo(
        w + (tailWidth * 0.5), h + 1.0, // 控制点（稍微向下凸一点）
        w - (tailWidth * 0.2), h,       // 终点
      );
      // 3) 向内连接到底边
      path.lineTo(w - (tailWidth * 0.8), h);

      // 6. 底边
      path.lineTo(rLarge, h);
      // 7. 左下圆角
      path.quadraticBezierTo(0, h, 0, h - rLarge);
      // 8. 左边
      path.lineTo(0, rLarge);
      // 9. 左上圆角
      path.quadraticBezierTo(0, 0, rLarge, 0);
      path.close();

    } else if (showTail && !isMe) {
      // --- 左侧气泡：尾巴在左下角 (镜像逻辑) ---
      // 1. 从顶部左端开始
      path.moveTo(rLarge, 0);
      // 2. 左上圆角
      path.quadraticBezierTo(0, 0, 0, rLarge);
      // 3. 左边
      path.lineTo(0, h - tailHeight);
      // 4. 关键：绘制 Telegram 风格左下角尖角
      // 路径：顺时针。从左边下部 (0, h-tailHeight) 开始
      // 1) 向下绘制一段弧度
      path.cubicTo(
        0, h - (tailHeight * 0.4),   // 控制点 1
        0, h - (tailHeight * 0.2),   // 控制点 2
        -(tailWidth * 0.2), h,       // 终点
      );
      // 2) 绘制尖角末梢
      path.quadraticBezierTo(
        -(tailWidth * 0.5), h + 1.0, // 控制点
        (tailWidth * 0.2), h,        // 终点
      );
      // 3) 向内连接到底边
      path.lineTo((tailWidth * 0.8), h);

      // 5. 底边
      path.lineTo(w - rLarge, h);
      // 6. 右下圆角
      path.quadraticBezierTo(w, h, w, h - rLarge);
      // 7. 右边
      path.lineTo(w, rLarge);
      // 8. 右上圆角
      path.quadraticBezierTo(w, 0, w - rLarge, 0);
      path.close();

    } else {
      // 无尾巴：四角圆角矩形
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h),
          const Radius.circular(rLarge),
        ),
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ChatBubblePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isMe != isMe ||
        oldDelegate.showTail != showTail;
  }
}