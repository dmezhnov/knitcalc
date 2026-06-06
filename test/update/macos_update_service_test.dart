import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/macos/macos_update_service_io.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_path_provider.dart';
import 'support/fake_release_server.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('macos_update_service_test');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('checkForUpdate', () {
    test('returns update info for a newer macOS release', () async {
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-macos-9.9.9.zip',
        assetBytes: utf8.encode('bundle'),
      );
      addTearDown(server.stop);

      final service = MacosUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_) async {},
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(9, 9, 9));
      expect(info.url, server.assetUrl);
    });

    test('returns null when the release is not newer', () async {
      final server = await FakeReleaseServer.start(
        tag: 'v1.0.0+0',
        assetName: 'knitcalc-macos-1.0.0.zip',
      );
      addTearDown(server.stop);

      final service = MacosUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the release endpoint errors', () async {
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-macos-9.9.9.zip',
        releaseStatus: 500,
      );
      addTearDown(server.stop);

      final service = MacosUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });
  });

  group('startUpdate', () {
    test(
      'downloads the archive and hands the swap script to the launcher',
      () async {
        final body = utf8.encode('PK-fake-macos-zip');
        final server = await FakeReleaseServer.start(
          assetName: 'knitcalc-macos-9.9.9.zip',
          assetBytes: body,
        );
        addTearDown(server.stop);

        String? launchedScript;
        final progress = <double>[];

        final service = MacosUpdateService(
          const AppVersion(1, 0, 0),
          releaseUrl: server.releaseUrl,
          executablePath: '/Apps/knitcalc.app/Contents/MacOS/knitcalc',
          launch: (script) async => launchedScript = script,
        );

        final info = await service.checkForUpdate();
        await service.startUpdate(info!, onProgress: progress.add);

        // The asset was fetched once and written to the temp dir verbatim.
        expect(server.assetRequests, 1);
        final archive = File('${tmp.path}/knitcalc-update.zip');
        expect(archive.existsSync(), isTrue);
        expect(archive.readAsBytesSync(), body);

        // Progress was reported through to completion.
        expect(progress, isNotEmpty);
        expect(progress.last, 1.0);

        // The launcher got the real swap script, targeting the .app bundle
        // derived from the injected executable path and the downloaded archive.
        expect(launchedScript, isNotNull);
        expect(launchedScript, contains('"/Apps/knitcalc.app"'));
        expect(launchedScript, contains('"${tmp.path}/knitcalc-update.zip"'));
        expect(launchedScript, contains('open "/Apps/knitcalc.app"'));
      },
    );
  });
}
