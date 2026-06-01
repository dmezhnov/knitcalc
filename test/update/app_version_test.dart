import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('parses major.minor.patch+build', () {
      final version = AppVersion.tryParse('1.2.3+4');

      expect(version, const AppVersion(1, 2, 3, 4));
    });

    test('defaults build to zero when absent', () {
      expect(AppVersion.tryParse('1.2.3'), const AppVersion(1, 2, 3));
    });

    test('fills missing minor and patch with zero', () {
      expect(AppVersion.tryParse('2'), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse('2.5'), const AppVersion(2, 5, 0));
    });

    test('strips a leading v from git tags', () {
      expect(AppVersion.tryParse('v1.1.1+0'), const AppVersion(1, 1, 1));
      expect(AppVersion.tryParse('V1.1.1'), const AppVersion(1, 1, 1));
    });

    test('trims surrounding whitespace', () {
      expect(AppVersion.tryParse('  1.0.0  '), const AppVersion(1, 0, 0));
    });

    test('returns null for unparsable input', () {
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse('abc'), isNull);
      expect(AppVersion.tryParse('1.2.3.4'), isNull);
      expect(AppVersion.tryParse('1.2.3+4+5'), isNull);
      expect(AppVersion.tryParse('1.-2.3'), isNull);
      expect(AppVersion.tryParse('1.x.0'), isNull);
    });
  });

  group('AppVersion comparison', () {
    test('orders by major, then minor, then patch', () {
      expect(
        const AppVersion(1, 0, 0).isOlderThan(const AppVersion(2, 0, 0)),
        isTrue,
      );
      expect(
        const AppVersion(1, 2, 0).isOlderThan(const AppVersion(1, 3, 0)),
        isTrue,
      );
      expect(
        const AppVersion(1, 2, 3).isOlderThan(const AppVersion(1, 2, 4)),
        isTrue,
      );
    });

    test('uses build only as a tie-breaker', () {
      expect(
        const AppVersion(1, 2, 3, 1).isOlderThan(const AppVersion(1, 2, 3, 2)),
        isTrue,
      );
      expect(
        const AppVersion(1, 2, 4).isOlderThan(const AppVersion(1, 2, 3, 9)),
        isFalse,
      );
    });

    test('equal versions are not older than each other', () {
      expect(
        const AppVersion(1, 1, 1).isOlderThan(const AppVersion(1, 1, 1)),
        isFalse,
      );
    });

    test('parsed pubspec version compares against a newer git tag', () {
      final current = AppVersion.tryParse('1.1.1+0')!;
      final latest = AppVersion.tryParse('v1.2.0+3')!;

      expect(current.isOlderThan(latest), isTrue);
    });
  });

  group('AppVersion.toString', () {
    test('omits a zero build', () {
      expect(const AppVersion(1, 2, 3).toString(), '1.2.3');
    });

    test('includes a non-zero build', () {
      expect(const AppVersion(1, 2, 3, 4).toString(), '1.2.3+4');
    });
  });
}
