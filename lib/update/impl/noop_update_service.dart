import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/update_service.dart';

/// Update service that never reports an update.
///
/// Used for channels where the platform or an external daemon handles updates
/// itself (snap, flatpak, MSIX, Mac App Store) and as the default during
/// Phase 1 while concrete implementations are not wired up yet.
class NoopUpdateService implements UpdateService {
  const NoopUpdateService();

  @override
  Future<UpdateInfo?> checkForUpdate() async => null;

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    DownloadControl? control,
  }) async {}
}
