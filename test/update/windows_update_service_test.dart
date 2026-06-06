import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/windows/windows_update_service_io.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_path_provider.dart';
import 'support/fake_release_server.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('windows_update_service_test');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('checkForUpdate', () {
    test('returns update info for a newer Windows release', () async {
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-windows-x64-9.9.9.zip',
        assetBytes: utf8.encode('bundle'),
      );
      addTearDown(server.stop);

      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_, _, _) async {},
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(9, 9, 9));
      expect(info.url, server.assetUrl);
    });

    test('returns null when the release is not newer', () async {
      final server = await FakeReleaseServer.start(
        tag: 'v1.0.0+0',
        assetName: 'knitcalc-windows-x64-1.0.0.zip',
      );
      addTearDown(server.stop);

      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
        launch: (_, _, _) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the release endpoint errors', () async {
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-windows-x64-9.9.9.zip',
        releaseStatus: 500,
      );
      addTearDown(server.stop);

      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        releaseUrl: server.releaseUrl,
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
        releaseUrl: server.releaseUrl,
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
