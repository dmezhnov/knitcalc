import 'package:knitcalc/update/update_info.dart';

/// Reports download progress as a fraction in `[0, 1]`.
///
/// Channels that cannot measure progress (e.g. the web reload) simply never
/// invoke it, leaving the UI to show an indeterminate indicator.
typedef UpdateProgressCallback = void Function(double fraction);

/// Abstraction over a per-channel update mechanism.
///
/// A concrete implementation is chosen by `createUpdateService` based on the
/// detected `Channel`. The app talks only to this interface, so adding a new
/// channel never touches call sites.
abstract interface class UpdateService {
  /// Checks the channel's source for a newer version.
  ///
  /// Returns an [UpdateInfo] when an update is available, or `null` when the
  /// app is up to date or the check could not be completed (e.g. offline).
  Future<UpdateInfo?> checkForUpdate();

  /// Starts the update described by [info].
  ///
  /// Depending on [UpdateInfo.action] this triggers an in-app flow, opens an
  /// external URL, or is a no-op for externally managed channels. When the
  /// mechanism downloads a payload it reports progress through [onProgress].
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
  });
}
