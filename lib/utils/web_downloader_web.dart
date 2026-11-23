import 'package:web/web.dart' as web;

/// web 端：通过创建一个带 download 属性的 <a> 标签并点击，
/// 让浏览器直接下载该 URL，浏览器会在下载按钮处立即显示进度条。
void triggerBrowserDownload(Uri url, String fileName) {
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url.toString()
    ..download = fileName
    ..target = '_blank'
    ..rel = 'noopener';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
}
