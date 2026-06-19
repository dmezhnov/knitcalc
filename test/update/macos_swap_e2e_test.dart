import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/impl/macos/macos_swap_logic.dart';

/// Minimal but valid bundle Info.plist so `open` can launch the stub at the end
/// of the swap script without erroring.
const String _infoPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>run</string>
  <key>CFBundleIdentifier</key><string>com.knitcalc.swaptest</string>
  <key>CFBundleName</key><string>knitcalc</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
''';

/// End-to-end exercise of the real macOS swap script on a macOS host: zips a stub
/// `.app` with `ditto` exactly as the release pipeline does, runs the actual
/// `buildMacosUpdateScript` output through `/bin/sh` (real `ditto` + `open`), and
/// verifies the whole `.app` is replaced only after the running process exits.
/// Skipped off macOS.
void main() {
  test(
    'detached script replaces the .app via ditto after the app exits',
    () async {
      final work = Directory.systemTemp.createTempSync('macos_swap_e2e');
      addTearDown(() => work.deleteSync(recursive: true));

      const appName = 'knitcalc.app';

      // Pre-existing install: an old bundle (with a file that must NOT survive a
      // full replace) plus an unrelated sibling that must.
      final install = Directory('${work.path}/Applications')..createSync();
      final oldBundle = '${install.path}/$appName';
      Directory('$oldBundle/Contents/MacOS').createSync(recursive: true);
      File('$oldBundle/Contents/MacOS/knitcalc').writeAsStringSync('OLD');
      File('$oldBundle/Contents/stale.txt').writeAsStringSync('stale');
      File('${install.path}/keep.txt').writeAsStringSync('sibling');

      // New bundle, zipped the way `mise`/CI does: top entry is `knitcalc.app/`.
      final src = Directory('${work.path}/src')..createSync();
      final newBundle = '${src.path}/$appName';
      Directory('$newBundle/Contents/MacOS').createSync(recursive: true);
      File('$newBundle/Contents/MacOS/knitcalc').writeAsStringSync('NEW');
      final run = File('$newBundle/Contents/MacOS/run')
        ..writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', run.path]);
      File('$newBundle/Contents/Info.plist').writeAsStringSync(_infoPlist);

      final archive = '${work.path}/update.zip';
      final ditto = Process.runSync('ditto', [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        newBundle,
        archive,
      ]);
      expect(ditto.exitCode, 0, reason: '${ditto.stderr}');

      // A short-lived process the script must wait on before swapping.
      final parent = await Process.start('sleep', ['1']);

      final script = buildMacosUpdateScript(
        pid: parent.pid,
        archivePath: archive,
        stagingDir: '${work.path}/staging',
        appBundlePath: oldBundle,
      );
      final scriptFile = File('${work.path}/swap.sh')
        ..writeAsStringSync(script);
      await Process.start('/bin/sh', [
        scriptFile.path,
      ], mode: ProcessStartMode.detached);

      // Swap is done once the new binary is in place and the archive is gone.
      final swapped = File('$oldBundle/Contents/MacOS/knitcalc');
      await _waitFor(
        () =>
            swapped.existsSync() &&
            swapped.readAsStringSync() == 'NEW' &&
            !File(archive).existsSync(),
      );

      // Whole .app replaced (stale file gone), sibling kept, staging cleaned up.
      expect(swapped.readAsStringSync(), 'NEW');
      expect(File('$oldBundle/Contents/stale.txt').existsSync(), isFalse);
      expect(File('${install.path}/keep.txt').existsSync(), isTrue);
      expect(Directory('${work.path}/staging').existsSync(), isFalse);
    },
    skip: Platform.isMacOS ? false : 'macOS-only swap e2e',
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('timed out waiting for the swap to complete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
