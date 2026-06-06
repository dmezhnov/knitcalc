import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/impl/linux/github_linux_logic.dart';

/// End-to-end exercise of the real Linux swap script on a Linux host: builds a
/// tarball, runs the actual `buildLinuxUpdateScript` output through `/bin/sh`
/// with real `tar`, and verifies the bundle is replaced and the app relaunched
/// only after the "running" process exits. Skipped off Linux.
void main() {
  test(
    'detached script unpacks the new bundle and relaunches after exit',
    () async {
      final work = Directory.systemTemp.createTempSync('linux_swap_e2e');
      addTearDown(() => work.deleteSync(recursive: true));

      // Pre-existing install with a stale binary and an unrelated user file.
      final install = Directory('${work.path}/install')..createSync();
      File('${install.path}/knitcalc').writeAsStringSync('OLD');
      File('${install.path}/keep.txt').writeAsStringSync('user-data');

      // New bundle, tarred the way the release pipeline produces it.
      final src = Directory('${work.path}/src')..createSync();
      File('${src.path}/knitcalc').writeAsStringSync('NEW');
      File('${src.path}/data.txt').writeAsStringSync('new-data');
      final archive = '${work.path}/update.tar.gz';
      final tar = Process.runSync('tar', [
        '-czf',
        archive,
        '-C',
        src.path,
        '.',
      ]);
      expect(tar.exitCode, 0, reason: '${tar.stderr}');

      // Relaunch target stands in for the app executable; it records that it ran.
      final marker = '${work.path}/relaunched';
      final relaunch = File('${work.path}/relaunch.sh')
        ..writeAsStringSync('#!/bin/sh\necho ok > "$marker"\n');
      Process.runSync('chmod', ['+x', relaunch.path]);

      // A short-lived process the script must wait on before swapping.
      final parent = await Process.start('sleep', ['1']);

      final script = buildLinuxUpdateScript(
        pid: parent.pid,
        archivePath: archive,
        installDir: install.path,
        executablePath: relaunch.path,
      );
      final scriptFile = File('${work.path}/swap.sh')
        ..writeAsStringSync(script);
      await Process.start('/bin/sh', [
        scriptFile.path,
      ], mode: ProcessStartMode.detached);

      await _waitFor(() => File(marker).existsSync());

      // Bundle replaced, sibling kept, archive cleaned up, app relaunched.
      expect(File('${install.path}/knitcalc').readAsStringSync(), 'NEW');
      expect(File('${install.path}/data.txt').readAsStringSync(), 'new-data');
      expect(File('${install.path}/keep.txt').existsSync(), isTrue);
      expect(File(archive).existsSync(), isFalse);
      expect(File(marker).readAsStringSync().trim(), 'ok');
    },
    skip: Platform.isLinux ? false : 'Linux-only swap e2e',
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
