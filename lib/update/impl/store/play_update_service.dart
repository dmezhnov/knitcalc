import 'package:in_app_update/in_app_update.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/update_service.dart';

/// Normalised result of a Play update check, decoupled from the plugin's
/// `AppUpdateInfo` (which has no public constructor, so cannot be faked).
class PlayUpdateStatus {
  const PlayUpdateStatus({required this.flexibleAvailable, this.versionCode});

  /// An update exists and the flexible (background) flow is allowed.
  final bool flexibleAvailable;

  /// Android version code of the available update, when reported. Play exposes
  /// no marketing version, only this integer.
  final int? versionCode;
}

/// Thin seam over the `in_app_update` plugin so [PlayUpdateService] is testable
/// without a device and without constructing plugin types.
abstract interface class PlayInAppUpdate {
  Future<PlayUpdateStatus> check();

  /// Starts the flexible download (Play shows its own consent dialog, then
  /// downloads in the background). Resolves `true` once downloaded, `false`
  /// when the user declined.
  Future<bool> startFlexible();

  /// Installs a downloaded flexible update; this restarts the app.
  Future<void> complete();
}

/// Real seam backed by the `in_app_update` plugin (Android / Google Play only).
class PluginPlayInAppUpdate implements PlayInAppUpdate {
  const PluginPlayInAppUpdate();

  @override
  Future<PlayUpdateStatus> check() async {
    final info = await InAppUpdate.checkForUpdate();

    return PlayUpdateStatus(
      flexibleAvailable:
          info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.flexibleUpdateAllowed,
      versionCode: info.availableVersionCode,
    );
  }

  @override
  Future<bool> startFlexible() async {
    final result = await InAppUpdate.startFlexibleUpdate();
    return result == AppUpdateResult.success;
  }

  @override
  Future<void> complete() => InAppUpdate.completeFlexibleUpdate();
}

/// Returns the Google Play update service.
UpdateService createPlayUpdateService() => PlayUpdateService();

/// Update service for Google Play builds using Play In-App Updates (flexible).
///
/// Play itself reports whether an update is available, so there is no GitHub
/// version comparison and no store-review lag. The update downloads and
/// installs through Play from inside the app; [startUpdate] runs the whole
/// flexible flow (download then install, which restarts the app).
class PlayUpdateService implements UpdateService {
  PlayUpdateService({PlayInAppUpdate? api})
    : _api = api ?? const PluginPlayInAppUpdate();

  final PlayInAppUpdate _api;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final PlayUpdateStatus status;

    try {
      status = await _api.check();
    } on Object {
      // Not installed from Play, offline, or the API is unavailable: skip.
      return null;
    }

    if (!status.flexibleAvailable) {
      return null;
    }

    return UpdateInfo(
      // Play reports a version code, not a marketing version: keep it as the
      // build component so the resume-dedup guard distinguishes releases, and
      // leave versionLabel null so the banner shows the generic message.
      latestVersion: AppVersion(0, 0, 0, status.versionCode ?? 0),
      action: UpdateAction.inApp,
    );
  }

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    DownloadControl? control,
  }) async {
    // in_app_update does not surface byte progress for the flexible download,
    // so the progress dialog stays indeterminate (onProgress is never called).
    final downloaded = await _api.startFlexible();

    if (!downloaded) {
      // User declined Play's consent dialog: not an error, just leave the
      // banner to be shown again by the caller.
      return;
    }

    await _api.complete();
  }
}
