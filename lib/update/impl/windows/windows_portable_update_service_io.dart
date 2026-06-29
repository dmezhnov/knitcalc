import 'dart:io';

import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/impl/download_file_io.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/impl/windows/windows_portable_swap_logic.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:path_provider/path_provider.dart';

/// Spawns the detached updater and terminates the app. Injectable for tests.
typedef UpdateLauncher = Future<void> Function(String scriptText);

UpdateService createWindowsPortableUpdateService(AppVersion? current) {
  // Only a real Windows desktop swaps a portable bundle; other dart:io targets
  // (Linux/macOS builds of this factory) stay no-op.
  if (!Platform.isWindows) {
    return const NoopUpdateService();
  }

  return WindowsPortableUpdateService(current);
}

/// Self-updater for a portable Windows copy of the loose
/// `knitcalc-windows-x64-*.zip` (extracted by hand, not installed by the Inno
/// installer — so [windowsChannelForExecutable] found no `install_source`
/// marker next to the exe).
///
/// Reads the available version from the remote store-versions document (the
/// `windowsPortable` entry carries the zip's download url, written by release
/// CI), downloads the zip (reporting progress) and hands off to a detached
/// PowerShell script that swaps the portable folder's files in place once the
/// app exits, then relaunches. Unlike [Channel.windowsManual] this never runs
/// the installer — running it would drop a second, installed copy under
/// `…\Programs\KnitCalc` alongside the portable one.
class WindowsPortableUpdateService implements UpdateService {
  WindowsPortableUpdateService(
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
      versions['windowsPortable'],
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
    // Forward slashes work in Windows APIs (and PowerShell) and keep the path
    // valid when these service tests run off Windows.
    final archive = File('${dir.path}/knitcalc-update.zip');
    await downloadFileWithControl(
      client: _httpClient,
      url: Uri.parse(url),
      dest: archive,
      onProgress: onProgress,
      control: control,
    );

    final executable = _executablePath;
    final script = buildWindowsPortableUpdateScript(
      pid: pid,
      archivePath: archive.path,
      stagingDir: '${dir.path}/knitcalc-update-staging',
      installDir: File(executable).parent.path,
      executablePath: executable,
    );

    // Hands off to the detached script and quits the app so it can swap the
    // bundle; control does not return here on the default launcher.
    await _launch(script);
  }
}

/// Writes the updater script to a temp file, launches it detached via
/// PowerShell, and exits so the script can replace the running bundle once the
/// process is gone (the files unlock on exit).
Future<void> _defaultLaunch(String scriptText) async {
  final dir = await getTemporaryDirectory();
  final script = File('${dir.path}/knitcalc-update.ps1');
  await script.writeAsString(scriptText);

  await Process.start('powershell', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    script.path,
  ], mode: ProcessStartMode.detached);

  exit(0);
}
