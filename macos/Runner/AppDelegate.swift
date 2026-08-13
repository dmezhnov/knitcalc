import Cocoa
import FlutterMacOS

// No @main here: main.swift is the entry point, so `--version` can be answered
// before AppKit starts (see macos/Runner/main.swift).
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
