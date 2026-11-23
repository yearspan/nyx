import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 全屏二维码扫码页（基于 mobile_scanner，支持相机和相册识别）
class QrScannerV2 extends StatefulWidget {
  final void Function(String) onScan;
  const QrScannerV2({required this.onScan, super.key});

  @override
  QrScannerV2State createState() => QrScannerV2State();
}

class QrScannerV2State extends State<QrScannerV2> {
  late final MobileScannerController _controller;
  bool _flashOn = false;
  bool _scanned = false;
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    Logs().w('扫描结果: $raw');
    if (raw == null || raw.isEmpty) return;
    _scanned = true;
    if (!mounted) return;
    // 由路由的 onScan 统一 pop 并携带结果，避免双重 pop
    widget.onScan(raw);
  }

  Future<void> _toggleFlash() async {
    try {
      await _controller.toggleTorch();
      if (mounted) {
        setState(() {
          _flashOn = _controller.value.torchState == TorchState.on;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickFromGallery() async {
    if (_analyzing) return;
    final l10n = L10n.of(context);
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      setState(() => _analyzing = true);
      // 加超时保护，避免 analyzeImage 在某些图片上一直 pending
      BarcodeCapture? capture;
      try {
        capture = await _controller
            .analyzeImage(picked.path)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        if (!mounted) return;
        V2Toast.show(l10n.qrScanTimeout);
        setState(() => _analyzing = false);
        return;
      }
      if (!mounted) return;
      if (capture == null || capture.barcodes.isEmpty) {
        V2Toast.show(l10n.qrScanNotFound);
        setState(() => _analyzing = false);
        return;
      }
      final raw = capture.barcodes.first.rawValue;
      Logs().w('相册识别结果: $raw');
      if (raw == null || raw.isEmpty) {
        V2Toast.show(l10n.qrScanEmpty);
        setState(() => _analyzing = false);
        return;
      }
      _scanned = true;
      widget.onScan(raw);
    } catch (e) {
      if (!mounted) return;
      V2Toast.show('${l10n.qrScanFailed}: $e');
      setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 全屏相机
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // 自定义扫码框遮罩（带四角直角标记）
          _ScanOverlay(),
          // 顶部导航栏（透明沉浸，白色纯图标返回）
          V2AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            circularBack: false,
            backIcon: Icons.arrow_back_ios_new,
          ),
          // 扫码框下方提示文字
          Positioned(
            top: MediaQuery.of(context).size.height / 2 + 130,
            left: 0,
            right: 0,
            child: Text(
              l10n.qrScanHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 底部按钮区
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BottomAction(
                  icon: Icons.image_outlined,
                  label: l10n.gallery,
                  onTap: _pickFromGallery,
                  loading: _analyzing,
                ),
                _BottomAction(
                  icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                  label: l10n.torch,
                  onTap: _toggleFlash,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 扫码框遮罩 + 四角直角标记
class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const cutOut = 220.0;
    final left = (size.width - cutOut) / 2;
    final top = (size.height - cutOut) / 2;
    return IgnorePointer(
      child: Stack(
        children: [
          // 半透明黑色遮罩 + 中间方形镂空
          CustomPaint(
            size: Size.infinite,
            painter: _MaskPainter(left: left, top: top, size: cutOut),
          ),
          // 四角直角标记
          Positioned(
            left: left,
            top: top,
            child: const _Corner(corner: _CornerType.topLeft, length: 40, width: 3),
          ),
          Positioned(
            right: size.width - left - cutOut,
            top: top,
            child: const _Corner(corner: _CornerType.topRight, length: 40, width: 3),
          ),
          Positioned(
            left: left,
            bottom: size.height - top - cutOut,
            child: const _Corner(corner: _CornerType.bottomLeft, length: 40, width: 3),
          ),
          Positioned(
            right: size.width - left - cutOut,
            bottom: size.height - top - cutOut,
            child: const _Corner(corner: _CornerType.bottomRight, length: 40, width: 3),
          ),
        ],
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final double left;
  final double top;
  final double size;
  _MaskPainter({required this.left, required this.top, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()..color = Color(0x8C000000);
    final cutOut = Rect.fromLTWH(left, top, size, size);
    final fullPath = Path()
      ..addRect(Offset.zero & canvasSize)
      ..addRect(cutOut)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(fullPath, paint);
  }

  @override
  bool shouldRepaint(covariant _MaskPainter old) =>
      left != old.left || top != old.top || size != old.size;
}

enum _CornerType { topLeft, topRight, bottomLeft, bottomRight }

class _Corner extends StatelessWidget {
  final _CornerType corner;
  final double length;
  final double width;
  const _Corner({
    required this.corner,
    required this.length,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    const color = Colors.white;
    // ignore: prefer_const_declarations
    final h = SizedBox(width: length, height: width, child: ColoredBox(color: color));
    // ignore: prefer_const_declarations
    final v = SizedBox(width: width, height: length, child: ColoredBox(color: color));
    Widget result;
    switch (corner) {
      case _CornerType.topLeft:
        result = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [h, v],
        );
        break;
      case _CornerType.topRight:
        result = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [h, v],
        );
        break;
      case _CornerType.bottomLeft:
        result = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [v, h],
        );
        break;
      case _CornerType.bottomRight:
        result = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [v, h],
        );
        break;
    }
    return SizedBox(
      width: length,
      height: length,
      child: Stack(
        children: [
          Positioned(
            left: corner == _CornerType.topLeft || corner == _CornerType.bottomLeft ? 0 : null,
            right: corner == _CornerType.topRight || corner == _CornerType.bottomRight ? 0 : null,
            top: corner == _CornerType.topLeft || corner == _CornerType.topRight ? 0 : null,
            bottom: corner == _CornerType.bottomLeft || corner == _CornerType.bottomRight ? 0 : null,
            child: result,
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 28),
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
