import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/macos/macos_update_service_io.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_path_provider.dart';
import 'support/fake_release_server.dart';
import 'support/fake_store_versions.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('macos_update_service_test');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('checkForUpdate', () {
    test('returns update info for a newer macOS version', () async {
      final service = MacosUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'macos': const RemoteEntry(
            version: AppVersion(9, 9, 9),
            label: '9.9.9',
            url: 'https://cdn.example.com/knitcalc-macos-9.9.9.zip',
          ),
        }),
        launch: (_) async {},
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(9, 9, 9));
      expect(info.url, 'https://cdn.example.com/knitcalc-macos-9.9.9.zip');
    });

    test('returns null when the version is not newer', () async {
      final service = MacosUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'macos': const RemoteEntry(
            version: AppVersion(1, 0, 0),
            label: '1.0.0',
            url: 'https://cdn.example.com/x.zip',
          ),
        }),
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the fetch fails', () async {
      final service = MacosUpdateService(
        const AppVersion(1, 0, 0),
        fetch: failingStoreVersions(),
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
          fetch: fakeStoreVersions({
            'macos': RemoteEntry(
              version: const AppVersion(9, 9, 9),
              label: '9.9.9',
              url: server.assetUrl,
              size: body.length,
            ),
          }),
          executablePath: '/Apps/knitcalc.app/Contents/MacOS/knitcalc',
          launch: (script) async => launchedScript = script,
        );

        final info = await service.checkForUpdate();
        await service.startUpdate(
          info!,
          onProgress: (p) => progress.add(p.fraction ?? 0),
        );

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
