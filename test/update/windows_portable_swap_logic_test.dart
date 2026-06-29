import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/impl/windows/windows_portable_swap_logic.dart';

void main() {
  group('buildWindowsPortableUpdateScript', () {
    final script = buildWindowsPortableUpdateScript(
      pid: 4242,
      archivePath: r'C:\Temp\knitcalc-update.zip',
      stagingDir: r'C:\Temp\knitcalc-update-staging',
      installDir: r'C:\Users\me\Portable Apps\knitcalc',
      executablePath: r'C:\Users\me\Portable Apps\knitcalc\knitcalc.exe',
    );

    test('waits for the running pid to exit before swapping', () {
      expect(script, contains('Get-Process -Id 4242'));
      // The extract must come after the wait loop, never before.
      expect(
        script.indexOf('Get-Process -Id 4242'),
        lessThan(script.indexOf('Expand-Archive')),
      );
    });

    test('extracts the zip into a staging dir', () {
      expect(
        script,
        contains(
          "Expand-Archive -LiteralPath 'C:\\Temp\\knitcalc-update.zip' "
          "-DestinationPath 'C:\\Temp\\knitcalc-update-staging' -Force",
        ),
      );
    });

    test('copies the staged files over the install dir in place', () {
      expect(
        script,
        contains(
          "Copy-Item -Path (Join-Path 'C:\\Temp\\knitcalc-update-staging' '*') "
          "-Destination 'C:\\Users\\me\\Portable Apps\\knitcalc' "
          '-Recurse -Force',
        ),
      );
    });

    test('removes the archive and relaunches the executable', () {
      expect(
        script,
        contains(
          "Remove-Item -LiteralPath 'C:\\Temp\\knitcalc-update.zip' -Force",
        ),
      );
      expect(
        script,
        contains(
          'Start-Process -FilePath '
          "'C:\\Users\\me\\Portable Apps\\knitcalc\\knitcalc.exe' "
          "-WorkingDirectory 'C:\\Users\\me\\Portable Apps\\knitcalc'",
        ),
      );
    });

    test('keeps the PowerShell automatic var literal (not interpolated)', () {
      expect(script, contains(r"$ErrorActionPreference = 'Stop'"));
    });

    test('doubles embedded single quotes in paths', () {
      final quoted = buildWindowsPortableUpdateScript(
        pid: 1,
        archivePath: r"C:\o'brien\u.zip",
        stagingDir: r'C:\s',
        installDir: r'C:\i',
        executablePath: r'C:\i\knitcalc.exe',
      );
      expect(quoted, contains(r"'C:\o''brien\u.zip'"));
    });
  });
}
