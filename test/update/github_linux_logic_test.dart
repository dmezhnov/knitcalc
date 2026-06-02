import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/linux/github_linux_logic.dart';
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
          'name': 'knitcalc-linux-x64-1.3.0+0.tar.gz',
          'browser_download_url': 'https://example.com/linux.tar.gz',
        },
      ],
};

void main() {
  group('isLinuxTarballAsset', () {
    test('matches the linux bundle tarball', () {
      expect(isLinuxTarballAsset('knitcalc-linux-x64-1.4.1+4.tar.gz'), isTrue);
    });

    test('ignores the web tarball', () {
      expect(isLinuxTarballAsset('knitcalc-web-1.4.1+4.tar.gz'), isFalse);
    });

    test('ignores other platforms', () {
      expect(isLinuxTarballAsset('knitcalc-1.4.1+4.apk'), isFalse);
      expect(isLinuxTarballAsset('knitcalc-windows-x64-1.4.1.zip'), isFalse);
    });
  });

  group('findLinuxTarballAsset', () {
    test('picks the linux tarball and ignores the web tarball', () {
      final asset = findLinuxTarballAsset(
        _release(
          assets: [
            {
              'name': 'knitcalc-web-1.3.0+0.tar.gz',
              'browser_download_url': 'https://example.com/web.tar.gz',
            },
            {
              'name': 'knitcalc-linux-x64-1.3.0+0.tar.gz',
              'browser_download_url': 'https://example.com/linux.tar.gz',
            },
          ],
        ),
      );

      expect(asset, isNotNull);
      expect(asset!.downloadUrl, 'https://example.com/linux.tar.gz');
    });

    test('returns null when there is no linux tarball', () {
      expect(
        findLinuxTarballAsset(
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

  group('evaluateGithubTarballUpdate', () {
    test('offers the tarball when the release is newer', () {
      final info = evaluateGithubTarballUpdate(
        AppVersion.tryParse('1.2.0+1'),
        _release(body: 'What is new'),
      );

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(1, 3, 0));
      expect(info.action, UpdateAction.inApp);
      expect(info.url, 'https://example.com/linux.tar.gz');
      expect(info.releaseNotes, 'What is new');
    });

    test('returns null when already up to date', () {
      expect(
        evaluateGithubTarballUpdate(AppVersion.tryParse('1.3.0'), _release()),
        isNull,
      );
    });

    test('returns null when the running build is newer', () {
      expect(
        evaluateGithubTarballUpdate(AppVersion.tryParse('2.0.0'), _release()),
        isNull,
      );
    });

    test('returns null when the current version is unknown', () {
      expect(evaluateGithubTarballUpdate(null, _release()), isNull);
    });

    test('returns null when the tag is unparsable', () {
      expect(
        evaluateGithubTarballUpdate(
          AppVersion.tryParse('1.2.0'),
          _release(tag: 'nightly'),
        ),
        isNull,
      );
    });

    test('returns null when a newer release has no linux tarball', () {
      expect(
        evaluateGithubTarballUpdate(
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
