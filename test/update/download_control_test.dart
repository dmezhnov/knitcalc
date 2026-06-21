import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/download_control.dart';

void main() {
  group('cancel', () {
    test('flips isCancelled and completes whenCancelled', () async {
      final control = DownloadControl();
      expect(control.isCancelled, isFalse);

      var fired = false;
      final waiter = control.whenCancelled.then((_) => fired = true);

      control.cancel();
      await waiter;

      expect(control.isCancelled, isTrue);
      expect(fired, isTrue);
    });

    test('cancelling twice is a safe no-op', () {
      final control = DownloadControl();
      control.cancel();
      // A second cancel must not throw (StateError on a completed Completer).
      expect(control.cancel, returnsNormally);
      expect(control.isCancelled, isTrue);
    });
  });

  group('pause/resume', () {
    test('pause sets isPaused and notifies pausedListenable', () {
      final control = DownloadControl();
      var notifications = 0;
      control.pausedListenable.addListener(() => notifications++);

      expect(control.isPaused, isFalse);
      control.pause();
      expect(control.isPaused, isTrue);
      expect(notifications, 1);

      control.resume();
      expect(control.isPaused, isFalse);
      expect(notifications, 2);
    });

    test('waitWhilePaused resolves immediately when not paused', () async {
      final control = DownloadControl();
      await control.waitWhilePaused().timeout(const Duration(seconds: 1));
    });

    test('waitWhilePaused blocks until resume', () async {
      final control = DownloadControl();
      control.pause();

      var resumed = false;
      final waiter = control.waitWhilePaused().then((_) => resumed = true);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(resumed, isFalse);

      control.resume();
      await waiter;
      expect(resumed, isTrue);
    });

    test('cancel unblocks a paused waiter', () async {
      final control = DownloadControl();
      control.pause();

      final waiter = control.waitWhilePaused();
      control.cancel();

      await waiter.timeout(const Duration(seconds: 1));
      expect(control.isPaused, isFalse);
      expect(control.isCancelled, isTrue);
    });

    test('pause after cancel is ignored', () {
      final control = DownloadControl();
      control.cancel();
      control.pause();
      expect(control.isPaused, isFalse);
    });
  });
}
