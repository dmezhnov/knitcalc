import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/impl/linux/linux_swap_logic.dart';

void main() {
  group('buildLinuxUpdateScript', () {
    final script = buildLinuxUpdateScript(
      pid: 4242,
      archivePath: '/tmp/knitcalc-update.tar.gz',
      installDir: '/home/u/Apps/knitcalc',
      executablePath: '/home/u/Apps/knitcalc/knitcalc',
    );

    test('waits for the running pid to exit before swapping', () {
      expect(script, contains('kill -0 4242'));
      // The unpack must come after the wait loop, never before.
      expect(
        script.indexOf('kill -0 4242'),
        lessThan(script.indexOf('tar -xzf')),
      );
    });

    test('unpacks the archive over the install directory', () {
      expect(
        script,
        contains(
          'tar -xzf "/tmp/knitcalc-update.tar.gz" -C "/home/u/Apps/knitcalc"',
        ),
      );
    });

    test('removes the archive and relaunches the executable', () {
      expect(script, contains('rm -f "/tmp/knitcalc-update.tar.gz"'));
      expect(script, contains('exec "/home/u/Apps/knitcalc/knitcalc"'));
    });
  });
}
