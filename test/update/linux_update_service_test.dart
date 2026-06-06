import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/linux/linux_update_service_io.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_path_provider.dart';
import 'support/fake_release_server.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('linux_update_service_test');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('checkForUpdate', () {
    test('returns update info for a newer Linux release', () async {
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-linux-x64-9.9.9.tar.gz',
        assetBytes: utf8.encode('bundle'),
      );
      addTearDown(server.stop);

      final service = LinuxUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_) async {},
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(9, 9, 9));
      expect(info.url, server.assetUrl);
      expect(info.downloadSize, utf8.encode('bundle').length);
    });

    test('returns null when the release is not newer', () async {
      final server = await FakeReleaseServer.start(
        tag: 'v1.0.0+0',
        assetName: 'knitcalc-linux-x64-1.0.0.tar.gz',
      );
      addTearDown(server.stop);

      final service = LinuxUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the release endpoint errors', () async {
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-linux-x64-9.9.9.tar.gz',
        releaseStatus: 503,
      );
      addTearDown(server.stop);

      final service = LinuxUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
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
          releaseUrl: server.releaseUrl,
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
