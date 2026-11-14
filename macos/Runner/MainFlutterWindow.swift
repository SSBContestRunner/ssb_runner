import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Kept alive for the window's lifetime; it owns both platform channels.
  private var audioOutputProbe: AudioOutputProbe?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    audioOutputProbe = AudioOutputProbe(
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}
