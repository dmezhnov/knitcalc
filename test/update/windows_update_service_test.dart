import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
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
            url: 'https://cdn.example.com/knitcalc-setup-x64-9.9.9.exe',
            size: 1234,
          ),
        }),
        launch: (_) async {},
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.latestVersion, const AppVersion(9, 9, 9));
      expect(info.action, UpdateAction.inApp);
      expect(info.url, 'https://cdn.example.com/knitcalc-setup-x64-9.9.9.exe');
      expect(info.downloadSize, 1234);
    });

    test('returns null when the version is not newer', () async {
      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'windows': const RemoteEntry(
            version: AppVersion(1, 0, 0),
            label: '1.0.0',
            url: 'https://cdn.example.com/x.exe',
          ),
        }),
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the document has no windows entry', () async {
      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions(const {}),
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('throws when the fetch fails (unreachable source)', () async {
      final service = WindowsUpdateService(
        const AppVersion(1, 0, 0),
        fetch: failingStoreVersions(),
        launch: (_) async {},
      );

      expect(service.checkForUpdate(), throwsA(isA<UpdateCheckException>()));
    });
  });

  group('startUpdate', () {
    test('downloads the installer and hands it to the launcher', () async {
      final body = utf8.encode('MZ-fake-windows-installer');
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-setup-x64-9.9.9.exe',
        assetBytes: body,
      );
      addTearDown(server.stop);

      String? launchedInstaller;
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
        launch: (installer) async => launchedInstaller = installer,
      );

      final info = await service.checkForUpdate();
      await service.startUpdate(
        info!,
        onProgress: (p) => progress.add(p.fraction ?? 0),
      );

      expect(server.assetRequests, 1);
      final installer = File('${tmp.path}/knitcalc-setup.exe');
      expect(installer.existsSync(), isTrue);
      expect(installer.readAsBytesSync(), body);

      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);

      // The launcher is handed the downloaded installer; it runs it silently and
      // the installer swaps the bundle in place and relaunches.
      expect(launchedInstaller, '${tmp.path}/knitcalc-setup.exe');
    });
  });
}
