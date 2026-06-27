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

/// Spawns the downloaded installer detached and terminates the app. Injectable
/// for tests. Receives the path to the freshly downloaded setup executable.
typedef InstallerLauncher = Future<void> Function(String installerPath);

/// Silent-install switches for the Inno Setup installer:
/// `/VERYSILENT /SUPPRESSMSGBOXES` runs without UI, `/NORESTART` suppresses a
/// machine reboot, and the custom `/RELAUNCH` flag tells the installer's `[Run]`
/// section to start KnitCalc again once the swap is done (see
/// packaging/inno/knitcalc.iss). A fresh winget/manual install omits `/RELAUNCH`
/// so it does not auto-launch the app.
const List<String> installerSilentArgs = [
  '/VERYSILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/RELAUNCH',
];

UpdateService createWindowsUpdateService(AppVersion? current) {
  // Only a real Windows desktop (incl. under Wine/Proton) runs the installer;
  // other dart:io targets (Linux/macOS builds of this factory) stay no-op.
  if (!Platform.isWindows) {
    return const NoopUpdateService();
  }

  return WindowsUpdateService(current);
}

/// Self-updater for Windows apps installed by running the Inno Setup installer
/// (`knitcalc-setup-x64-*.exe` GitHub Release asset) directly — not via a
/// package manager. winget installs are detected as a separate channel and
/// update with `winget upgrade` instead (see channel.dart).
///
/// Reads the available version from the remote store-versions document (see
/// remote/store_versions.dart — the `windows` entry carries the installer's
/// download url, written by release CI), downloads the installer (reporting
/// progress) and hands off to it: the app spawns the installer silently and
/// quits; the installer closes any running instance via the Windows Restart
/// Manager, replaces the per-user install in place (no UAC — it installs under
/// `%LOCALAPPDATA%\Programs`) and relaunches the app. Because the installer also
/// refreshes the Add/Remove Programs version, winget stays consistent. Scoop and
/// Chocolatey installs are detected as their own channels and update through the
/// manager instead; Microsoft Store (MSIX) installs are handled by a
/// [NoopUpdateService]. The installer itself still downloads from the GitHub
/// CDN; only the version check moved off the rate-limited GitHub API.
class WindowsUpdateService implements UpdateService {
  WindowsUpdateService(
    this._current, {
    HttpClient? httpClient,
    InstallerLauncher? launch,
    RemoteVersionsFetcher? fetch,
  }) : _httpClient = httpClient ?? HttpClient(),
       _launch = launch ?? _defaultLaunch,
       _fetch = fetch ?? fetchStoreVersions;

  final AppVersion? _current;
  final HttpClient _httpClient;
  final InstallerLauncher _launch;
  final RemoteVersionsFetcher _fetch;

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
    final installer = File('${dir.path}/knitcalc-setup.exe');
    await downloadFileWithControl(
      client: _httpClient,
      url: Uri.parse(url),
      dest: installer,
      onProgress: onProgress,
      control: control,
    );

    // Hands off to the detached installer and quits the app so it can swap the
    // bundle; control does not return here on the default launcher.
    await _launch(installer.path);
  }
}

/// Launches the downloaded installer detached and silent, then exits so the
/// installer can replace the running bundle once this process is gone (the
/// Windows Restart Manager also closes a lingering instance). The installer
/// relaunches the app itself via the `/RELAUNCH` flag.
Future<void> _defaultLaunch(String installerPath) async {
  await Process.start(
    installerPath,
    installerSilentArgs,
    mode: ProcessStartMode.detached,
  );

  exit(0);
}
