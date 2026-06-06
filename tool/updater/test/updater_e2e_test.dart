import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

/// End-to-end exercise of the real `knitcalc_updater` entrypoint on Windows:
/// runs it against a live "parent" process and a stub bundle, and verifies it
/// waits for the parent to exit, swaps the bundle in place, removes the archive
/// and relaunches the executable. This covers the Windows-only pieces (FFI
/// `WaitForSingleObject`, detached relaunch) that the cross-platform
/// `bundle_apply` unit tests cannot. Skipped off Windows.
void main() {
  test(
    'waits for the parent, applies the bundle and relaunches',
    () async {
      final work = Directory.systemTemp.createTempSync('updater_e2e');
      addTearDown(() => work.deleteSync(recursive: true));

      // A tiny relaunch target: writes a marker file (path from the env it
      // inherits) so the test can confirm the updater relaunched it.
      final markerPath = '${work.path}\\relaunched.txt';
      final markerSrc = File('${work.path}\\marker.dart')
        ..writeAsStringSync(
          "import 'dart:io';\n"
          'void main() {\n'
          "  final p = Platform.environment['KNITCALC_MARKER'];\n"
          "  if (p != null) File(p).writeAsStringSync('relaunched');\n"
          '}\n',
        );
      final markerExe = '${work.path}\\marker.exe';
      final compile = Process.runSync('dart', [
        'compile',
        'exe',
        markerSrc.path,
        '-o',
        markerExe,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stdout}${compile.stderr}');

      // Pre-existing install with a stale binary and an unrelated user file.
      final install = Directory('${work.path}\\install')..createSync();
      File('${install.path}\\knitcalc.exe').writeAsStringSync('OLD');
      File('${install.path}\\keep.txt').writeAsStringSync('user-data');

      // New bundle as a zip, the shape the updater expects.
      final zip = Archive()
        ..addFile(_entry('knitcalc.exe', 'NEW'))
        ..addFile(_entry('data/app.txt', 'new-data'));
      final archivePath = '${work.path}\\update.zip';
      File(archivePath).writeAsBytesSync(ZipEncoder().encodeBytes(zip));

      // A short-lived "parent" the updater must wait on before swapping.
      final parent = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        'Start-Sleep -Milliseconds 800',
      ]);

      final updaterEntry =
          '${Directory.current.path}\\bin\\knitcalc_updater.dart';
      final run = await Process.run(
        'dart',
        [
          'run',
          updaterEntry,
          '${parent.pid}',
          archivePath,
          install.path,
          markerExe,
        ],
        environment: {'KNITCALC_MARKER': markerPath},
      );
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');

      await _waitFor(() => File(markerPath).existsSync());

      // Bundle replaced, sibling kept, new file added, archive removed.
      expect(File('${install.path}\\knitcalc.exe').readAsStringSync(), 'NEW');
      expect(
        File('${install.path}\\data\\app.txt').readAsStringSync(),
        'new-data',
      );
      expect(File('${install.path}\\keep.txt').existsSync(), isTrue);
      expect(File(archivePath).existsSync(), isFalse);
      // The updater relaunched the executable (marker written).
      expect(File(markerPath).readAsStringSync(), 'relaunched');
    },
    skip: Platform.isWindows ? false : 'Windows-only updater e2e',
  );
}

ArchiveFile _entry(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile(name, bytes.length, bytes);
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('timed out waiting for the updater to finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
