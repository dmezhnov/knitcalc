import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/impl/store/store_listing_service.dart';
import 'package:knitcalc/update/update_info.dart';

import 'support/fake_store_versions.dart';

void main() {
  group('checkForUpdate', () {
    test(
      'offers the store listing when the store published a newer version',
      () async {
        final service = StoreListingUpdateService(
          channel: Channel.androidFdroid,
          current: const AppVersion(1, 8, 0),
          fetch: fakeStoreVersions({
            'fdroid': const RemoteEntry(
              version: AppVersion(1, 9, 0),
              label: '1.9.0',
            ),
          }),
          launchUrl: (_) async => true,
        );

        final info = await service.checkForUpdate();

        expect(info, isNotNull);
        expect(info!.latestVersion, const AppVersion(1, 9, 0));
        expect(info.action, UpdateAction.openUrl);
        expect(
          info.url,
          'https://f-droid.org/packages/io.github.dmezhnov.knitcalc/',
        );
      },
    );

    test('returns null when the store version is not newer', () async {
      final service = StoreListingUpdateService(
        channel: Channel.androidSamsung,
        current: const AppVersion(1, 9, 0),
        fetch: fakeStoreVersions({
          'samsung': const RemoteEntry(
            version: AppVersion(1, 9, 0),
            label: '1.9.0',
          ),
        }),
        launchUrl: (_) async => true,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the document has no entry for the store', () async {
      final service = StoreListingUpdateService(
        channel: Channel.androidHuawei,
        current: const AppVersion(1, 8, 0),
        fetch: fakeStoreVersions(const {}),
        launchUrl: (_) async => true,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('throws when the fetch fails (unreachable source)', () async {
      final service = StoreListingUpdateService(
        channel: Channel.androidAmazon,
        current: const AppVersion(1, 8, 0),
        fetch: failingStoreVersions(),
        launchUrl: (_) async => true,
      );

      expect(service.checkForUpdate(), throwsA(isA<UpdateCheckException>()));
    });
  });

  group('startUpdate', () {
    test('opens the store deep link first, https fallback next', () async {
      final attempted = <Uri>[];

      final service = StoreListingUpdateService(
        channel: Channel.androidSamsung,
        current: const AppVersion(1, 8, 0),
        fetch: fakeStoreVersions({
          'samsung': const RemoteEntry(
            version: AppVersion(1, 9, 0),
            label: '1.9.0',
          ),
        }),
        launchUrl: (url) async {
          attempted.add(url);
          // Deep link fails (store app missing) → fall through to https.
          return url.scheme == 'https';
        },
      );

      final info = await service.checkForUpdate();
      await service.startUpdate(info!);

      expect(attempted.first.scheme, 'samsungapps');
      expect(attempted.last.scheme, 'https');
      expect(
        attempted.last.toString(),
        'https://galaxystore.samsung.com/detail/io.github.dmezhnov.knitcalc',
      );
    });

    test('throws when no listing url can be opened', () async {
      final service = StoreListingUpdateService(
        channel: Channel.androidAccrescent,
        current: const AppVersion(1, 8, 0),
        fetch: fakeStoreVersions({
          'accrescent': const RemoteEntry(
            version: AppVersion(1, 9, 0),
            label: '1.9.0',
          ),
        }),
        launchUrl: (_) async => false,
      );

      final info = await service.checkForUpdate();

      expect(() => service.startUpdate(info!), throwsStateError);
    });
  });
}
