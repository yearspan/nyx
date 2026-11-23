import 'dart:ui' as ui;

import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// V2 风格的二维码查看页：白底卡片 + V2AppBar，下载直接保存到系统相册
Future<void> showQrCodeViewer(BuildContext context, String content) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => QrCodeViewer(content: content)),
  );
}

class QrCodeViewer extends StatefulWidget {
  final String content;

  const QrCodeViewer({required this.content, super.key});

  @override
  State<QrCodeViewer> createState() => _QrCodeViewerState();
}

class _QrCodeViewerState extends State<QrCodeViewer> {
  bool _saving = false;
  final GlobalKey _repaintKey = GlobalKey();

  /// 截图整个二维码卡片并返回 PNG 字节
  Future<Uint8List?> _captureCard() async {
    final boundary =
        _repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // 放大 3 倍提高清晰度
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  /// 直接保存到系统相册
  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _captureCard();
      if (bytes == null) throw Exception('capture failed');
      final success = await saveImageBytes(
        bytes,
        name: 'QR_Code_${widget.content}.png',
      );
      if (!mounted) return;
      V2Toast.show(
        success
            ? L10n.of(context).savedToGallery
            : L10n.of(context).oopsSomethingWentWrong,
      );
    } catch (e) {
      if (mounted) {
        V2Toast.show('$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final inviteLink = 'https://nstalk.space/#/${widget.content}';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: V2Theme.of(context).scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              V2AppBar(
                backgroundColor: V2Theme.of(context).scaffoldBackground,
                title: l10n.qrCode,
                backIcon: Icons.close,
                onBack: () => Navigator.of(context).pop(),
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (PlatformInfos.isMobile)
                      V2CircleIconButton(
                        icon: Icons.ios_share,
                        onTap: () => FluffyShare.share(inviteLink, context),
                      ),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: _saving
                          ? Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : V2CircleIconButton(
                              icon: Icons.download_outlined,
                              onTap: _saveToGallery,
                            ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        // 二维码必须是深色模块 + 浅色背景才能被扫描，
                        // 因此卡片背景始终为白色，不随主题变化
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 240,
                            height: 240,
                            child: PrettyQrView.data(
                              data: inviteLink,
                              decoration: const PrettyQrDecoration(
                                shape: PrettyQrSmoothSymbol(
                                  roundFactor: 1,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                          Text(
                            widget.content,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
