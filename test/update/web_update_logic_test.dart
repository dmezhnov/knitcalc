import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/web/web_update_logic.dart';
import 'package:knitcalc/update/update_info.dart';

void main() {
  group('parseDeployedVersion', () {
    test('combines version and build_number', () {
      final version = parseDeployedVersion({
        'version': '1.2.0',
        'build_number': '3',
      });

      expect(version, const AppVersion(1, 2, 0, 3));
    });

    test('tolerates a missing build_number', () {
      expect(
        parseDeployedVersion({'version': '1.2.0'}),
        const AppVersion(1, 2, 0),
      );
    });

    test('returns null without a usable version', () {
      expect(parseDeployedVersion({'build_number': '3'}), isNull);
      expect(parseDeployedVersion({'version': ''}), isNull);
      expect(parseDeployedVersion({'version': 42}), isNull);
    });
  });

  group('evaluateWebUpdate', () {
    final deployed = {'version': '1.3.0', 'build_number': '0'};

    test('offers an in-app reload when the deployment is newer', () {
      final info = evaluateWebUpdate(AppVersion.tryParse('1.2.0+1'), deployed);

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(1, 3, 0));
      expect(info.action, UpdateAction.inApp);
    });

    test('returns null when already up to date', () {
      expect(
        evaluateWebUpdate(AppVersion.tryParse('1.3.0+0'), deployed),
        isNull,
      );
    });

    test('returns null when the running build is newer', () {
      expect(evaluateWebUpdate(AppVersion.tryParse('1.4.0'), deployed), isNull);
    });

    test('returns null when the current version is unknown', () {
      expect(evaluateWebUpdate(null, deployed), isNull);
    });

    test('returns null when the payload is unparsable', () {
      expect(
        evaluateWebUpdate(AppVersion.tryParse('1.2.0'), {'foo': 'bar'}),
        isNull,
      );
    });

    test('uses build_number as a tie-breaker for an update', () {
      final info = evaluateWebUpdate(AppVersion.tryParse('1.3.0+1'), {
        'version': '1.3.0',
        'build_number': '2',
      });

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(1, 3, 0, 2));
    });
  });
}
