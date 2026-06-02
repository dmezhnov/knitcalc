import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/android/github_release_logic.dart';
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
          'name': 'knitcalc-1.3.0+0.apk',
          'browser_download_url': 'https://example.com/knitcalc.apk',
        },
      ],
};

void main() {
  group('findApkAsset', () {
    test('picks the .apk asset and ignores the .aab bundle', () {
      final asset = findApkAsset(
        _release(
          assets: [
            {
              'name': 'knitcalc-1.3.0+0.aab',
              'browser_download_url': 'https://example.com/bundle.aab',
            },
            {
              'name': 'knitcalc-1.3.0+0.apk',
              'browser_download_url': 'https://example.com/app.apk',
            },
          ],
        ),
      );

      expect(asset, isNotNull);
      expect(asset!.downloadUrl, 'https://example.com/app.apk');
    });

    test('returns null when there is no APK', () {
      expect(
        findApkAsset(
          _release(
            assets: [
              {
                'name': 'knitcalc-linux-x64.tar.gz',
                'browser_download_url': 'https://example.com/linux.tar.gz',
              },
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('evaluateGithubApkUpdate', () {
    test('offers the APK when the release is newer', () {
      final info = evaluateGithubApkUpdate(
        AppVersion.tryParse('1.2.0+1'),
        _release(body: 'What is new'),
      );

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(1, 3, 0));
      expect(info.action, UpdateAction.inApp);
      expect(info.url, 'https://example.com/knitcalc.apk');
      expect(info.releaseNotes, 'What is new');
    });

    test('returns null when already up to date', () {
      expect(
        evaluateGithubApkUpdate(AppVersion.tryParse('1.3.0'), _release()),
        isNull,
      );
    });

    test('returns null when the running build is newer', () {
      expect(
        evaluateGithubApkUpdate(AppVersion.tryParse('2.0.0'), _release()),
        isNull,
      );
    });

    test('returns null when the current version is unknown', () {
      expect(evaluateGithubApkUpdate(null, _release()), isNull);
    });

    test('returns null when the tag is unparsable', () {
      expect(
        evaluateGithubApkUpdate(
          AppVersion.tryParse('1.2.0'),
          _release(tag: 'nightly'),
        ),
        isNull,
      );
    });

    test('returns null when a newer release has no APK', () {
      expect(
        evaluateGithubApkUpdate(
          AppVersion.tryParse('1.2.0'),
          _release(
            assets: [
              {
                'name': 'knitcalc-web.tar.gz',
                'browser_download_url': 'https://example.com/web.tar.gz',
              },
            ],
          ),
        ),
        isNull,
      );
    });
  });
}
