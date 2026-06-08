import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/store/play_update_service.dart';
import 'package:knitcalc/update/update_info.dart';

/// Fake seam over the in_app_update plugin.
class _FakePlay implements PlayInAppUpdate {
  _FakePlay({
    this.status = const PlayUpdateStatus(
      flexibleAvailable: true,
      versionCode: 30,
    ),
    this.checkThrows = false,
    this.downloaded = true,
  });

  PlayUpdateStatus status;
  bool checkThrows;
  bool downloaded;

  bool startCalled = false;
  bool completeCalled = false;

  @override
  Future<PlayUpdateStatus> check() async {
    if (checkThrows) {
      throw StateError('not installed from Play');
    }
    return status;
  }

  @override
  Future<bool> startFlexible() async {
    startCalled = true;
    return downloaded;
  }

  @override
  Future<void> complete() async {
    completeCalled = true;
  }
}

void main() {
  group('checkForUpdate', () {
    test(
      'returns an inApp update with a generic banner when available',
      () async {
        final service = PlayUpdateService(api: _FakePlay());

        final info = await service.checkForUpdate();

        expect(info, isNotNull);
        expect(info!.action, UpdateAction.inApp);
        // Play exposes no marketing version, so the banner stays generic.
        expect(info.versionLabel, isNull);
        // The version code rides in the build component for the dedup guard.
        expect(info.latestVersion.build, 30);
      },
    );

    test('returns null when no flexible update is available', () async {
      final service = PlayUpdateService(
        api: _FakePlay(
          status: const PlayUpdateStatus(flexibleAvailable: false),
        ),
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when the plugin throws (e.g. not from Play)', () async {
      final service = PlayUpdateService(api: _FakePlay(checkThrows: true));

      expect(await service.checkForUpdate(), isNull);
    });
  });

  group('startUpdate', () {
    UpdateInfo info() => const UpdateInfo(
      latestVersion: AppVersion(0, 0, 0, 30),
      action: UpdateAction.inApp,
    );

    test('completes the install after a successful download', () async {
      final fake = _FakePlay(downloaded: true);
      await PlayUpdateService(api: fake).startUpdate(info());

      expect(fake.startCalled, isTrue);
      expect(fake.completeCalled, isTrue);
    });

    test('does not install (or throw) when the user declines', () async {
      final fake = _FakePlay(downloaded: false);
      await PlayUpdateService(api: fake).startUpdate(info());

      expect(fake.startCalled, isTrue);
      expect(fake.completeCalled, isFalse);
    });
  });
}
