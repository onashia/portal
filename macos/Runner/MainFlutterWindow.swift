import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override public func order(
    _ place: NSWindow.OrderingMode,
    relativeTo otherWin: Int
  ) {
    super.order(place, relativeTo: otherWin)
    // Keep the native window hidden until Portal explicitly shows it so the
    // custom-themed first frame can appear without a white/native flash.
    hiddenWindowAtLaunch()
  }
}
