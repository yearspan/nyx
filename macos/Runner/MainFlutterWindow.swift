import Cocoa
import FlutterMacOS
import CoreGraphics
import window_manager

class MainFlutterWindow: NSWindow {
  /// 默认窗口尺寸。Flutter 模板默认 800x600 偏窄，聊天桌面端使用更宽的
  /// 1280x800；若屏幕可见区域更小，则限制为不超出屏幕。
  static let defaultWindowSize = NSSize(width: 1280, height: 800)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 在当前屏幕可见区域内居中放置默认尺寸窗口，保证一定在屏幕内。
    // 不使用 setFrameAutosaveName：它会与 AppKit 状态恢复耦合，
    // 在无历史 frame 或屏幕配置变化时可能把窗口恢复到屏幕外导致不可见。
    let visibleFrame =
      NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let width = min(Self.defaultWindowSize.width, visibleFrame.width)
    let height = min(Self.defaultWindowSize.height, visibleFrame.height)
    let origin = NSPoint(
      x: visibleFrame.midX - width / 2,
      y: visibleFrame.midY - height / 2
    )
    self.setFrame(
      NSRect(origin: origin, size: NSSize(width: width, height: height)),
      display: true
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 注册屏幕录制权限通道，供 Dart 端在开启屏幕共享前检查/请求 macOS TCC 权限。
    // 必须在 RegisterGeneratedPlugins 之后、engine 已就绪时注册。
    let screenPermissionChannel = FlutterMethodChannel(
      name: "nexora/screen_permission",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    screenPermissionChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "checkScreenCapturePermission":
        // CGPreflightScreenCaptureAccess 仅查询当前是否已授权，不弹窗。
        result(CGPreflightScreenCaptureAccess())

      case "requestScreenCapturePermission":
        // 主动触发系统授权弹窗。macOS 10.15+ 提供该 API。
        if #available(macOS 10.15, *) {
          let granted = CGRequestScreenCaptureAccess()
          DispatchQueue.main.async {
            result(granted)
          }
        } else {
          result(CGPreflightScreenCaptureAccess())
        }

      case "openScreenCaptureSettings":
        // 直接打开「系统设置 → 隐私与安全性 → 屏幕录制」面板。
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  /// 窗口首次被 AppKit 排列到屏幕前先隐藏，等 Dart 侧恢复完上次保存的
  /// 位置与尺寸后再调用 windowManager.show() 显示，避免默认窗口闪现后
  /// 再跳动到记忆位置。hiddenWindowAtLaunch 内部有 configured 标志，
  /// 仅在启动阶段生效一次，后续普通 order 操作不受影响。
  override public func order(
    _ place: NSWindow.OrderingMode,
    relativeTo otherWin: Int
  ) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
