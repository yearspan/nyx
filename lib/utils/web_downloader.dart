/// 非 web 平台的占位实现；web 端使用 [web_downloader_web.dart]。
/// 在非 web 平台不会被调用（调用处已用 [PlatformInfos.isWeb] 守卫）。
void triggerBrowserDownload(Uri url, String fileName) {
  // no-op
}
