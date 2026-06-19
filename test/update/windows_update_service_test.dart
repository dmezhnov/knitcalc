import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/impl/windows/windows_update_service_io.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_path_provider.dart';
import 'support/fake_release_server.dart';
import 'support/fake_store_versions.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('windows_update_service_test');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('checkForUpdate', () {
    test('returns update info for a newer Windows version', () async {
      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'windows': const RemoteEntry(
            version: AppVersion(9, 9, 9),
            label: '9.9.9',
            url: 'https://cdn.example.com/knitcalc-windows-x64-9.9.9.zip',
            size: 1234,
          ),
        }),
        launch: (_, _, _) async {},
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(9, 9, 9));
      expect(info.action, UpdateAction.inApp);
      expect(
        info.url,
        'https://cdn.example.com/knitcalc-windows-x64-9.9.9.zip',
      );
      expect(info.downloadSize, 1234);
    });

    test('returns null when the version is not newer', () async {
      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'windows': const RemoteEntry(
            version: AppVersion(1, 0, 0),
            label: '1.0.0',
            url: 'https://cdn.example.com/x.zip',
          ),
        }),
        launch: (_, _, _) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the document has no windows entry', () async {
      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions(const {}),
        launch: (_, _, _) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the fetch fails', () async {
      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: failingStoreVersions(),
        launch: (_, _, _) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });
  });

  group('startUpdate', () {
    test('downloads the archive and hands swap args to the launcher', () async {
      final body = utf8.encode('PK-fake-windows-zip');
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-windows-x64-9.9.9.zip',
        assetBytes: body,
      );
      addTearDown(server.stop);

      String? launchedArchive;
      String? launchedInstallDir;
      String? launchedExecutable;
      final progress = <double>[];

      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'windows': RemoteEntry(
            version: const AppVersion(9, 9, 9),
            label: '9.9.9',
            url: server.assetUrl,
            size: body.length,
          ),
        }),
        executablePath: '/Apps/knitcalc/knitcalc.exe',
        launch: (archive, installDir, executable) async {
          launchedArchive = archive;
          launchedInstallDir = installDir;
          launchedExecutable = executable;
        },
      );

      final info = await service.checkForUpdate();
      await service.startUpdate(
        info!,
        onProgress: (p) => progress.add(p.fraction ?? 0),
      );

      expect(server.assetRequests, 1);
      final archive = File('${tmp.path}/knitcalc-update.zip');
      expect(archive.existsSync(), isTrue);
      expect(archive.readAsBytesSync(), body);

      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);

      // The helper is handed the downloaded archive, the install dir (parent of
      // the injected executable) and the executable to relaunch.
      expect(launchedArchive, '${tmp.path}/knitcalc-update.zip');
      expect(launchedInstallDir, '/Apps/knitcalc');
      expect(launchedExecutable, '/Apps/knitcalc/knitcalc.exe');
    });
  });
}
