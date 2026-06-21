import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// Method channel shared with [MainActivity] for install-source detection and
/// driving the download foreground service.
const MethodChannel androidUpdateChannel = MethodChannel(
  'knitcalc/android_update',
);

/// Event channel over which the download foreground service streams progress and
/// terminal state. Each event is a map:
/// `{state: downloading|paused|done|cancelled|error, received: int, total: int}`.
const EventChannel androidUpdateProgressChannel = EventChannel(
  'knitcalc/android_update_progress',
);

UpdateService createAndroidUpdateService(AppVersion? current) {
  // Only Android can install an APK; other dart:io targets stay no-op.
  if (!Platform.isAndroid) {
    return const NoopUpdateService();
  }

  return AndroidUpdateService(current);
}

/// Supplies the device's primary ABI (e.g. `arm64-v8a`), or `null` when it
/// can't be determined — then the universal APK is used. Injected for tests.
typedef AbiProvider = Future<String?> Function();

/// Default [AbiProvider]: asks the platform for `Build.SUPPORTED_ABIS[0]`.
Future<String?> _primaryAbi() async {
  try {
    return await androidUpdateChannel.invokeMethod<String>('primaryAbi');
  } on PlatformException {
    return null;
  }
}

/// Sideload updater for APKs distributed via GitHub Releases.
///
/// Reads the available version from the remote store-versions document (the
/// `android` entry carries the APK download url, written by release CI). The
/// download itself runs in a native foreground service (so it survives the app
/// being backgrounded and shows an ongoing notification with progress and
/// Pause/Cancel actions); this class only starts it, mirrors its progress and
/// state into [onProgress]/[DownloadControl], and relays the dialog's controls
/// back to it. On completion the service hands the APK to the system installer.
/// Only the version check moved off the GitHub API — its 60/hour unauthenticated
/// limit is shared per IP and easily exhausted under carrier-grade NAT on mobile.
class AndroidUpdateService implements UpdateService {
  AndroidUpdateService(
    this._current, {
    RemoteVersionsFetcher? fetch,
    AbiProvider? abi,
  }) : _fetch = fetch ?? fetchStoreVersions,
       _abi = abi ?? _primaryAbi;

  final AppVersion? _current;
  final RemoteVersionsFetcher _fetch;
  final AbiProvider _abi;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final versions = await _fetch();
    final entry = versions['android'];

    // Prefer the device-ABI APK (~3x smaller) over the universal one; fall back
    // to the universal url/size when the ABI is unknown or has no variant.
    final asset = entry?.assetForAbi(await _abi());

    return evaluateRemoteUpdate(
      _current,
      entry,
      action: UpdateAction.inApp,
      url: asset?.url,
      downloadSize: asset?.size,
    );
  }

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    DownloadControl? control,
  }) async {
    final url = info.url;

    if (url == null) {
      return;
    }

    // Best-effort: ask for POST_NOTIFICATIONS (Android 13+). A denial only hides
    // the notification; the foreground download still runs.
    try {
      await androidUpdateChannel.invokeMethod<void>(
        'ensureNotificationPermission',
      );
    } on PlatformException {
      // Ignore — proceed without the notification.
    }

    final done = Completer<void>();

    // Relay the dialog's Pause/Resume and Cancel to the service.
    void pauseListener() {
      androidUpdateChannel.invokeMethod<void>(
        control!.isPaused ? 'pauseDownload' : 'resumeDownload',
      );
    }

    StreamSubscription<void>? cancelWatch;
    if (control != null) {
      control.pausedListenable.addListener(pauseListener);
      cancelWatch = control.whenCancelled.asStream().listen((_) {
        androidUpdateChannel.invokeMethod<void>('cancelDownload');
      });
    }

    // Subscribe before starting so no early event is missed. The notification's
    // own buttons mirror back here (downloading/paused) to keep the dialog and
    // the [control] in sync; the idempotent pause/resume avoids a feedback loop.
    final progressWatch = androidUpdateProgressChannel.receiveBroadcastStream().listen(
      (event) {
        final map = (event as Map).cast<Object?, Object?>();
        final state = map['state'] as String?;
        final received = (map['received'] as num?)?.toInt() ?? 0;
        final total = (map['total'] as num?)?.toInt() ?? -1;

        switch (state) {
          case 'downloading':
            control?.resume();
            if (onProgress != null && total > 0) {
              onProgress(DownloadProgress(received: received, total: total));
            }
          case 'paused':
            control?.pause();
            if (onProgress != null && total > 0) {
              onProgress(DownloadProgress(received: received, total: total));
            }
          case 'done':
            // Foreground: launch the installer from the Activity now. (If the
            // app is backgrounded the service's "downloaded" notification does
            // it on tap, since a service can't start an Activity in the back-
            // ground.) FLAG_ACTIVITY_NEW_TASK makes a re-launch harmless.
            final path = map['path'] as String?;
            if (path != null) {
              androidUpdateChannel.invokeMethod<void>('installApk', {
                'path': path,
              });
            }
            if (!done.isCompleted) done.complete();
          case 'cancelled':
            if (!done.isCompleted) {
              done.completeError(const UpdateCancelled());
            }
          case 'error':
            if (!done.isCompleted) {
              done.completeError(const HttpException('Update download failed'));
            }
        }
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
    );

    try {
      // Returns true when this version's APK was already fully downloaded: the
      // native side installs it straight away, so there is no download to await
      // (and no progress events to wait on, avoiding a start-up race).
      final reused =
          await androidUpdateChannel.invokeMethod<bool>('startDownload', {
            'url': url,
            // Lets the service reuse an already-downloaded APK and resume a
            // partial one (it keys the cache file by version and checks size).
            'size': info.downloadSize ?? -1,
            'version': info.versionLabel ?? info.latestVersion.toString(),
          }) ??
          false;

      if (!reused) {
        // Completes when the service reports done (installer already launched),
        // or throws UpdateCancelled / an error.
        await done.future;
      }
    } finally {
      await progressWatch.cancel();
      await cancelWatch?.cancel();
      control?.pausedListenable.removeListener(pauseListener);
    }
  }
}
