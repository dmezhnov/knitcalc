import 'dart:io';

import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/download_file_io.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:path_provider/path_provider.dart';

/// Spawns the detached updater helper and terminates the app. Injectable for
/// tests. Receives the downloaded archive, the install directory and the
/// executable to relaunch.
typedef UpdateLauncher =
    Future<void> Function(
      String archivePath,
      String installDir,
      String executablePath,
    );

/// Basename of the updater helper shipped inside the bundle (built by the
/// `mise build-windows` task via `dart compile exe bin/knitcalc_updater.dart`).
const String updaterExecutable = 'knitcalc_updater.exe';

UpdateService createWindowsUpdateService(AppVersion? current) {
  // Only a real Windows desktop (incl. under Wine/Proton) swaps its own bundle;
  // other dart:io targets (Linux/macOS builds of this factory) stay no-op.
  if (!Platform.isWindows) {
    return const NoopUpdateService();
  }

  return WindowsUpdateService(current);
}

/// Self-updater for manually installed Windows bundles distributed as the
/// `knitcalc-windows-x64-*.zip` GitHub Release asset.
///
/// Reads the available version from the remote store-versions document (see
/// remote/store_versions.dart — the `windows` entry carries the download url,
/// written by release CI), downloads the zip (reporting progress) and hands off
/// to the bundled updater helper ([updaterExecutable]): the app copies the
/// helper to a temp dir, spawns it detached with the running pid, and quits; the
/// helper waits for the app to exit (so the bundle's files unlock), unpacks the
/// zip over the install directory and relaunches. This works on both native
/// Windows and Wine/Proton — neither lets a running process replace its own open
/// files. Microsoft Store (MSIX) installs are handled by a [NoopUpdateService]
/// instead. The zip itself still downloads from the GitHub CDN; only the version
/// check moved off the rate-limited GitHub API.
class WindowsUpdateService implements UpdateService {
  WindowsUpdateService(
    this._current, {
    HttpClient? httpClient,
    UpdateLauncher? launch,
    RemoteVersionsFetcher? fetch,
    String? executablePath,
  }) : _httpClient = httpClient ?? HttpClient(),
       _launch = launch ?? _defaultLaunch,
       _fetch = fetch ?? fetchStoreVersions,
       _executablePath = executablePath ?? Platform.resolvedExecutable;

  final AppVersion? _current;
  final HttpClient _httpClient;
  final UpdateLauncher _launch;
  final RemoteVersionsFetcher _fetch;
  final String _executablePath;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final versions = await _fetch();

    return evaluateRemoteUpdate(
      _current,
      versions['windows'],
      action: UpdateAction.inApp,
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

    final dir = await getTemporaryDirectory();
    final archive = File('${dir.path}/knitcalc-update.zip');
    await downloadFileWithControl(
      client: _httpClient,
      url: Uri.parse(url),
      dest: archive,
      onProgress: onProgress,
      control: control,
    );

    final executable = _executablePath;
    final installDir = File(executable).parent.path;

    // Hands off to the detached helper and quits the app so it can swap the
    // bundle; control does not return here on the default launcher.
    await _launch(archive.path, installDir, executable);
  }
}

/// Copies the bundled updater helper to a temp dir, launches it detached with
/// the running pid and swap arguments, and exits so the helper can replace the
/// running bundle once this process is gone. The helper runs from temp (not the
/// install dir it overwrites) so it never locks its own target.
Future<void> _defaultLaunch(
  String archivePath,
  String installDir,
  String executablePath,
) async {
  final dir = await getTemporaryDirectory();
  final updater = File('${dir.path}/$updaterExecutable');
  File('$installDir/$updaterExecutable').copySync(updater.path);

  await Process.start(updater.path, [
    '$pid',
    archivePath,
    installDir,
    executablePath,
  ], mode: ProcessStartMode.detached);

  exit(0);
}
