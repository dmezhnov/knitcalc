import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/linux/linux_update_service_io.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_path_provider.dart';
import 'support/fake_release_server.dart';
import 'support/fake_store_versions.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('linux_update_service_test');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('checkForUpdate', () {
    test('returns update info for a newer Linux version', () async {
      final service = LinuxUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'linux': const RemoteEntry(
            version: AppVersion(9, 9, 9),
            label: '9.9.9',
            url: 'https://cdn.example.com/knitcalc-linux-x64-9.9.9.tar.gz',
            size: 2048,
          ),
        }),
        launch: (_) async {},
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(9, 9, 9));
      expect(
        info.url,
        'https://cdn.example.com/knitcalc-linux-x64-9.9.9.tar.gz',
      );
      expect(info.downloadSize, 2048);
    });

    test('returns null when the version is not newer', () async {
      final service = LinuxUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'linux': const RemoteEntry(
            version: AppVersion(1, 0, 0),
            label: '1.0.0',
            url: 'https://cdn.example.com/x.tar.gz',
          ),
        }),
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('throws when the fetch fails (unreachable source)', () async {
      final service = LinuxUpdateService(
        const AppVersion(1, 0, 0),
        fetch: failingStoreVersions(),
        launch: (_) async {},
      );

      expect(service.checkForUpdate(), throwsA(isA<UpdateCheckException>()));
    });
  });

  group('startUpdate', () {
    test(
      'downloads the tarball and hands the swap script to the launcher',
      () async {
        final body = utf8.encode('fake-linux-tarball');
        final server = await FakeReleaseServer.start(
          assetName: 'knitcalc-linux-x64-9.9.9.tar.gz',
          assetBytes: body,
        );
        addTearDown(server.stop);

        String? launchedScript;
        final progress = <double>[];

        final service = LinuxUpdateService(
          const AppVersion(1, 0, 0),
          fetch: fakeStoreVersions({
            'linux': RemoteEntry(
              version: const AppVersion(9, 9, 9),
              label: '9.9.9',
              url: server.assetUrl,
              size: body.length,
            ),
          }),
          executablePath: '/home/u/Apps/knitcalc/knitcalc',
          launch: (script) async => launchedScript = script,
        );

        final info = await service.checkForUpdate();
        await service.startUpdate(
          info!,
          onProgress: (p) => progress.add(p.fraction ?? 0),
        );

        expect(server.assetRequests, 1);
        final archive = File('${tmp.path}/knitcalc-update.tar.gz');
        expect(archive.existsSync(), isTrue);
        expect(archive.readAsBytesSync(), body);

        expect(progress, isNotEmpty);
        expect(progress.last, 1.0);

        // The launcher got the real swap script, unpacking the archive over the
        // install dir (parent of the injected executable) and relaunching it.
        expect(launchedScript, isNotNull);
        expect(launchedScript, contains('kill -0 '));
        expect(
          launchedScript,
          contains(
            'tar -xzf "${tmp.path}/knitcalc-update.tar.gz" '
            '-C "/home/u/Apps/knitcalc"',
          ),
        );
        expect(
          launchedScript,
          contains('exec "/home/u/Apps/knitcalc/knitcalc"'),
        );
      },
    );
  });
}
