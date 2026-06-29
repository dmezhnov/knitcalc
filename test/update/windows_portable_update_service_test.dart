import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/impl/windows/windows_portable_update_service_io.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_path_provider.dart';
import 'support/fake_release_server.dart';
import 'support/fake_store_versions.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('windows_portable_update_test');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('checkForUpdate', () {
    test('reads the windowsPortable entry, not the installer one', () async {
      final service = WindowsPortableUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          // The installer entry must be ignored by the portable service.
          'windows': const RemoteEntry(
            version: AppVersion(9, 9, 9),
            label: '9.9.9',
            url: 'https://cdn.example.com/knitcalc-setup-x64-9.9.9.exe',
          ),
          'windowsPortable': const RemoteEntry(
            version: AppVersion(9, 9, 9),
            label: '9.9.9',
            url: 'https://cdn.example.com/knitcalc-windows-x64-9.9.9.zip',
            size: 1234,
          ),
        }),
        launch: (_) async {},
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

    test('returns null when there is no windowsPortable entry', () async {
      final service = WindowsPortableUpdateService(
        const AppVersion(1, 0, 0),
        // Only the installer entry exists — portable has nothing to offer.
        fetch: fakeStoreVersions({
          'windows': const RemoteEntry(
            version: AppVersion(9, 9, 9),
            label: '9.9.9',
            url: 'https://cdn.example.com/x.exe',
          ),
        }),
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the version is not newer', () async {
      final service = WindowsPortableUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'windowsPortable': const RemoteEntry(
            version: AppVersion(1, 0, 0),
            label: '1.0.0',
            url: 'https://cdn.example.com/x.zip',
          ),
        }),
        launch: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('throws when the fetch fails (unreachable source)', () async {
      final service = WindowsPortableUpdateService(
        const AppVersion(1, 0, 0),
        fetch: failingStoreVersions(),
        launch: (_) async {},
      );

      expect(service.checkForUpdate(), throwsA(isA<UpdateCheckException>()));
    });
  });

  group('startUpdate', () {
    test('downloads the zip and hands a swap script to the launcher', () async {
      final body = utf8.encode('PK-fake-windows-zip');
      final server = await FakeReleaseServer.start(
        assetName: 'knitcalc-windows-x64-9.9.9.zip',
        assetBytes: body,
      );
      addTearDown(server.stop);

      String? launchedScript;
      final progress = <double>[];

      final service = WindowsPortableUpdateService(
        const AppVersion(1, 0, 0),
        fetch: fakeStoreVersions({
          'windowsPortable': RemoteEntry(
            version: const AppVersion(9, 9, 9),
            label: '9.9.9',
            url: server.assetUrl,
            size: body.length,
          ),
        }),
        launch: (script) async => launchedScript = script,
        executablePath: r'C:\Users\me\Portable\knitcalc\knitcalc.exe',
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

      // The launcher is handed the PowerShell swap script, which waits for this
      // process and replaces the portable folder's files in place, then
      // relaunches the executable it was told about. (The exact install-dir
      // derivation is OS-specific — File().parent only parses '\' on Windows —
      // so the script's -Destination path is asserted in the swap-logic test.)
      expect(launchedScript, isNotNull);
      expect(launchedScript, contains('Expand-Archive'));
      expect(
        launchedScript,
        contains(
          'Start-Process -FilePath '
          r"'C:\Users\me\Portable\knitcalc\knitcalc.exe'",
        ),
      );
    });
  });
}
