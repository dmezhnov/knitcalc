import 'package:knitcalc/update/update_info.dart';

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
  /// external URL, or is a no-op for externally managed channels.
  Future<void> startUpdate(UpdateInfo info);
}
