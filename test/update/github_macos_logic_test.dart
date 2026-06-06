import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/macos/github_macos_logic.dart';
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
          'name': 'knitcalc-macos-1.3.0+0.zip',
          'browser_download_url': 'https://example.com/macos.zip',
        },
      ],
};

void main() {
  group('isMacosZipAsset', () {
    test('matches the macOS bundle zip', () {
      expect(isMacosZipAsset('knitcalc-macos-1.4.1+4.zip'), isTrue);
    });

    test('ignores other zip bundles', () {
      expect(isMacosZipAsset('knitcalc-windows-x64-1.4.1+4.zip'), isFalse);
      expect(isMacosZipAsset('knitcalc-ios-unsigned-1.4.1+4.zip'), isFalse);
    });

    test('ignores other platforms', () {
      expect(isMacosZipAsset('knitcalc-1.4.1+4.apk'), isFalse);
      expect(isMacosZipAsset('knitcalc-linux-x64-1.4.1.tar.gz'), isFalse);
    });
  });

  group('findMacosZipAsset', () {
    test('picks the macOS zip and ignores the windows zip', () {
      final asset = findMacosZipAsset(
        _release(
          assets: [
            {
              'name': 'knitcalc-windows-x64-1.3.0+0.zip',
              'browser_download_url': 'https://example.com/windows.zip',
            },
            {
              'name': 'knitcalc-macos-1.3.0+0.zip',
              'browser_download_url': 'https://example.com/macos.zip',
            },
          ],
        ),
      );

      expect(asset, isNotNull);
      expect(asset!.downloadUrl, 'https://example.com/macos.zip');
    });

    test('returns null when there is no macOS zip', () {
      expect(
        findMacosZipAsset(
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

  group('evaluateGithubMacosUpdate', () {
    test('offers the zip when the release is newer', () {
      final info = evaluateGithubMacosUpdate(
        AppVersion.tryParse('1.2.0+1'),
        _release(body: 'What is new'),
      );

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(1, 3, 0));
      expect(info.action, UpdateAction.inApp);
      expect(info.url, 'https://example.com/macos.zip');
      expect(info.releaseNotes, 'What is new');
    });

    test('returns null when already up to date', () {
      expect(
        evaluateGithubMacosUpdate(AppVersion.tryParse('1.3.0'), _release()),
        isNull,
      );
    });

    test('returns null when the running build is newer', () {
      expect(
        evaluateGithubMacosUpdate(AppVersion.tryParse('2.0.0'), _release()),
        isNull,
      );
    });

    test('returns null when the current version is unknown', () {
      expect(evaluateGithubMacosUpdate(null, _release()), isNull);
    });

    test('returns null when the tag is unparsable', () {
      expect(
        evaluateGithubMacosUpdate(
          AppVersion.tryParse('1.2.0'),
          _release(tag: 'nightly'),
        ),
        isNull,
      );
    });

    test('returns null when a newer release has no macOS zip', () {
      expect(
        evaluateGithubMacosUpdate(
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
