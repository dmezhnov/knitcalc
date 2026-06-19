/// Derives the `.app` bundle path from a macOS [resolvedExecutable].
///
/// `Platform.resolvedExecutable` for a bundled app is
/// `<dir>/knitcalc.app/Contents/MacOS/knitcalc`; the bundle the updater replaces
/// is three path segments up. Kept as a pure function so it can be unit-tested
/// without a real macOS executable.
String macAppBundlePath(String resolvedExecutable) {
  final macosDir = _parent(resolvedExecutable); // .../Contents/MacOS
  final contentsDir = _parent(macosDir); // .../Contents

  return _parent(contentsDir); // .../knitcalc.app
}

/// Returns [path] with its last `/`-separated segment removed. Trailing slashes
/// are ignored, mirroring how the bundle path is laid out on macOS.
String _parent(String path) {
  var end = path.length;
  while (end > 0 && path[end - 1] == '/') {
    end--;
  }

  final slash = path.lastIndexOf('/', end - 1);
  if (slash <= 0) {
    return slash == 0 ? '/' : path.substring(0, end);
  }

  return path.substring(0, slash);
}

/// Builds the detached `/bin/sh` script that swaps in a downloaded macOS bundle.
///
/// The app must quit after spawning it: the script waits for [pid] to disappear
/// (so the running `.app` is no longer mapped), extracts [archivePath] — a
/// `ditto`-created zip whose top entry is the `.app` — into a fresh [stagingDir],
/// replaces [appBundlePath] with the new bundle, removes the archive and staging
/// dir, then relaunches via `open`. The new build then sees its own version on
/// next launch.
///
/// Unlike Windows/Wine, macOS does not lock the files of a running process, but
/// replacing a mapped `.app` in place can still crash the live app, so the swap
/// happens only after [pid] exits. Every path is baked in here (no runtime shell
/// variables) so paths with spaces stay correctly quoted; `ditto` preserves the
/// bundle's extended attributes and any code signature.
String buildMacosUpdateScript({
  required int pid,
  required String archivePath,
  required String stagingDir,
  required String appBundlePath,
}) =>
    '#!/bin/sh\n'
    '# KnitCalc self-update: wait for the running app to exit, replace the .app\n'
    '# bundle with the freshly downloaded one, then relaunch.\n'
    'set -e\n'
    'while kill -0 $pid 2>/dev/null; do\n'
    '  sleep 0.2\n'
    'done\n'
    'rm -rf "$stagingDir"\n'
    'mkdir -p "$stagingDir"\n'
    'ditto -x -k "$archivePath" "$stagingDir"\n'
    'rm -rf "$appBundlePath"\n'
    'mv "$stagingDir"/*.app "$appBundlePath"\n'
    'rm -f "$archivePath"\n'
    'rm -rf "$stagingDir"\n'
    'open "$appBundlePath"\n';
