import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/android/android_update_service_io.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/update_info.dart';

void main() {
  // An android entry carrying the universal APK plus two per-ABI variants.
  RemoteEntry androidEntry() => const RemoteEntry(
    version: AppVersion(1, 9, 0, 70),
    label: '1.9.0+70',
    url: 'https://cdn.example.com/universal.apk',
    size: 54000000,
    abis: {
      'arm64-v8a': RemoteAsset(
        url: 'https://cdn.example.com/arm64.apk',
        size: 19000000,
      ),
      'x86_64': RemoteAsset(
        url: 'https://cdn.example.com/x64.apk',
        size: 20000000,
      ),
    },
  );

  AndroidUpdateService service({required String? abi}) => AndroidUpdateService(
    const AppVersion(1, 8, 0, 60),
    fetch: () async => {'android': androidEntry()},
    abi: () async => abi,
  );

  group('checkForUpdate ABI selection', () {
    test('downloads the per-ABI APK matching the device', () async {
      final info = await service(abi: 'arm64-v8a').checkForUpdate();

      expect(info, isNotNull);
      expect(info!.url, 'https://cdn.example.com/arm64.apk');
      expect(info.downloadSize, 19000000);
      expect(info.action, UpdateAction.inApp);
    });

    test('falls back to the universal APK when the ABI is unknown', () async {
      final info = await service(abi: null).checkForUpdate();

      expect(info!.url, 'https://cdn.example.com/universal.apk');
      expect(info.downloadSize, 54000000);
    });

    test(
      'falls back to the universal APK for an ABI with no variant',
      () async {
        final info = await service(abi: 'armeabi-v7a').checkForUpdate();

        expect(info!.url, 'https://cdn.example.com/universal.apk');
        expect(info.downloadSize, 54000000);
      },
    );

    test('returns null when the running version is not older', () async {
      final svc = AndroidUpdateService(
        const AppVersion(1, 9, 0, 70),
        fetch: () async => {'android': androidEntry()},
        abi: () async => 'arm64-v8a',
      );

      expect(await svc.checkForUpdate(), isNull);
    });
  });
}
