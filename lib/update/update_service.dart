import 'package:knitcalc/update/update_info.dart';

/// Snapshot of an in-flight download: bytes received so far out of the total.
///
/// [total] is the payload size in bytes, or `-1` when the server omits a
/// Content-Length; [fraction] is then `null` and the UI shows an indeterminate
/// indicator without a byte count.
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});

  final int received;
  final int total;

  /// Completed fraction in `[0, 1]`, or `null` when [total] is unknown.
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

/// Reports download progress as bytes received out of the total.
///
/// Channels that cannot measure progress (e.g. the web reload) simply never
/// invoke it, leaving the UI to show an indeterminate indicator.
typedef UpdateProgressCallback = void Function(DownloadProgress progress);

/// Abstraction over a per-channel update mechanism.
///
/// A concrete implementation is chosen by `createUpdateService` based on the
/// detected `Channel`. The app talks only to this interface, so adding a new
/// channel never touches call sites.
abstract interface class UpdateService {
  /// Checks the channel's source for a newer version.
  ///
  /// Returns an [UpdateInfo] when an update is available, or `null` when the
  /// app is up to date. Network-backed implementations throw when the source
  /// can't be reached (e.g. offline or blocked) so the caller can tell a
  /// genuine "up to date" from a failed check and offer a retry; channels that
  /// resolve locally (e.g. a package manager) keep degrading silently.
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
