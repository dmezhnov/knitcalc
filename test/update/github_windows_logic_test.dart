import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/windows/github_windows_logic.dart';
import 'package:knitcalc/update/update_info.dart';

Map<String, dynamic> _release({
  String tag = 'v1.3.0+0',
  List<Map<String, String>>? assets,
  String? body,
}) => {
  'tag_name': tag,
  'body': ?body,
  'assets':
      assets ??
      [
        {
          'name': 'knitcalc-windows-x64-1.3.0+0.zip',
          'browser_download_url': 'https://example.com/windows.zip',
        },
      ],
};

void main() {
  group('isWindowsZipAsset', () {
    test('matches the windows bundle zip', () {
      expect(isWindowsZipAsset('knitcalc-windows-x64-1.4.1+4.zip'), isTrue);
    });

    test('ignores other zip bundles', () {
      expect(isWindowsZipAsset('knitcalc-macos-1.4.1+4.zip'), isFalse);
      expect(isWindowsZipAsset('knitcalc-ios-unsigned-1.4.1+4.zip'), isFalse);
    });

    test('ignores other platforms', () {
      expect(isWindowsZipAsset('knitcalc-1.4.1+4.apk'), isFalse);
      expect(isWindowsZipAsset('knitcalc-linux-x64-1.4.1.tar.gz'), isFalse);
    });
  });

  group('findWindowsZipAsset', () {
    test('picks the windows zip and ignores the macOS zip', () {
      final asset = findWindowsZipAsset(
        _release(
          assets: [
            {
              'name': 'knitcalc-macos-1.3.0+0.zip',
              'browser_download_url': 'https://example.com/macos.zip',
            },
            {
              'name': 'knitcalc-windows-x64-1.3.0+0.zip',
              'browser_download_url': 'https://example.com/windows.zip',
            },
          ],
        ),
      );

      expect(asset, isNotNull);
      expect(asset!.downloadUrl, 'https://example.com/windows.zip');
    });

    test('returns null when there is no windows zip', () {
      expect(
        findWindowsZipAsset(
          _release(
            assets: [
              {
                'name': 'knitcalc-1.3.0+0.apk',
                'browser_download_url': 'https://example.com/app.apk',
              },
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('evaluateGithubWindowsUpdate', () {
    test('offers the zip when the release is newer', () {
      final info = evaluateGithubWindowsUpdate(
        AppVersion.tryParse('1.2.0+1'),
        _release(body: 'What is new'),
      );

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(1, 3, 0));
      expect(info.action, UpdateAction.inApp);
      expect(info.url, 'https://example.com/windows.zip');
      expect(info.releaseNotes, 'What is new');
    });

    test('returns null when already up to date', () {
      expect(
        evaluateGithubWindowsUpdate(AppVersion.tryParse('1.3.0'), _release()),
        isNull,
      );
    });

    test('returns null when the running build is newer', () {
      expect(
        evaluateGithubWindowsUpdate(AppVersion.tryParse('2.0.0'), _release()),
        isNull,
      );
    });

    test('returns null when the current version is unknown', () {
      expect(evaluateGithubWindowsUpdate(null, _release()), isNull);
    });

    test('returns null when the tag is unparsable', () {
      expect(
        evaluateGithubWindowsUpdate(
          AppVersion.tryParse('1.2.0'),
          _release(tag: 'nightly'),
        ),
        isNull,
      );
    });

    test('returns null when a newer release has no windows zip', () {
      expect(
        evaluateGithubWindowsUpdate(
          AppVersion.tryParse('1.2.0'),
          _release(
            assets: [
              {
                'name': 'knitcalc-1.3.0+0.apk',
                'browser_download_url': 'https://example.com/app.apk',
              },
            ],
          ),
        ),
        isNull,
      );
    });
  });
}
