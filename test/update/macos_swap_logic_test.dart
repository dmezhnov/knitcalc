import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/impl/macos/macos_swap_logic.dart';

void main() {
  group('macAppBundlePath', () {
    test('strips Contents/MacOS/<exe> to the .app bundle', () {
      expect(
        macAppBundlePath('/Applications/knitcalc.app/Contents/MacOS/knitcalc'),
        '/Applications/knitcalc.app',
      );
    });

    test('handles a bundle in a path with spaces', () {
      expect(
        macAppBundlePath('/Users/me/My Apps/knitcalc.app/Contents/MacOS/run'),
        '/Users/me/My Apps/knitcalc.app',
      );
    });
  });

  group('buildMacosUpdateScript', () {
    final script = buildMacosUpdateScript(
      pid: 4242,
      archivePath: '/tmp/knitcalc-update.zip',
      stagingDir: '/tmp/knitcalc-update-staging',
      appBundlePath: '/Applications/knitcalc.app',
    );

    test('waits for the running pid to exit before swapping', () {
      expect(script, contains('kill -0 4242'));
      // The extraction must come after the wait loop, never before.
      expect(
        script.indexOf('kill -0 4242'),
        lessThan(script.indexOf('ditto -x -k')),
      );
    });

    test('extracts the archive into a fresh staging directory', () {
      expect(
        script,
        contains(
          'ditto -x -k "/tmp/knitcalc-update.zip" "/tmp/knitcalc-update-staging"',
        ),
      );
      // Staging is wiped before use so a stale prior attempt cannot leak in.
      expect(
        script.indexOf('rm -rf "/tmp/knitcalc-update-staging"'),
        lessThan(script.indexOf('ditto -x -k')),
      );
    });

    test('replaces the .app bundle with the extracted one', () {
      // The old bundle is removed, then the new one moved into its place.
      expect(script, contains('rm -rf "/Applications/knitcalc.app"'));
      expect(
        script,
        contains(
          'mv "/tmp/knitcalc-update-staging"/*.app "/Applications/knitcalc.app"',
        ),
      );
      expect(
        script.indexOf('rm -rf "/Applications/knitcalc.app"'),
        lessThan(script.indexOf('mv "/tmp/knitcalc-update-staging"/*.app')),
      );
    });

    test('removes the archive and relaunches the bundle', () {
      expect(script, contains('rm -f "/tmp/knitcalc-update.zip"'));
      expect(script, contains('open "/Applications/knitcalc.app"'));
    });
  });
}
