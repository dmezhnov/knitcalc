import Cocoa

// `knitcalc --version` must answer without starting AppKit: package managers
// (mise's registry test, our release smoke check) run it on machines with no
// window server, and Dart's main() only runs once the app is up. This file
// replaces @main on AppDelegate so the check happens before NSApplicationMain.
if CommandLine.arguments.contains("--version") {
  let info = Bundle.main.infoDictionary
  let name = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  let build = info?["CFBundleVersion"] as? String ?? "0"
  // Matches the Linux/Windows runners: the full pubspec version ("1.2.3+45").
  print("knitcalc \(name)+\(build)")
  exit(0)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
