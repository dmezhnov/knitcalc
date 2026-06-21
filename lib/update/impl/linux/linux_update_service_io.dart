import 'dart:io';

import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/download_file_io.dart';
import 'package:knitcalc/update/impl/linux/linux_swap_logic.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:path_provider/path_provider.dart';

/// Spawns the detached updater and terminates the app. Injectable for tests.
typedef UpdateLauncher = Future<void> Function(String scriptText);

UpdateService createLinuxUpdateService(AppVersion? current) {
  // Only a real Linux desktop swaps its own bundle; other dart:io targets
  // (macOS/Windows builds of this factory) stay no-op.
  if (!Platform.isLinux) {
    return const NoopUpdateService();
  }

  return LinuxUpdateService(current);
}

/// Self-updater for manually installed Linux bundles distributed as the
/// `knitcalc-linux-x64-*.tar.gz` GitHub Release asset.
///
/// Reads the available version from the remote store-versions document (the
/// `linux` entry carries the download url, written by release CI), downloads the
/// tarball (reporting progress) and hands off to a detached shell script that
/// unpacks it over the install directory once the app exits, then relaunches.
/// Package-managed installs (snap/flatpak/dpkg) are handled by a
/// [NoopUpdateService] instead — their daemon owns updates. The tarball still
/// downloads from the GitHub CDN; only the version check moved off the
/// rate-limited GitHub API.
class LinuxUpdateService implements UpdateService {
  LinuxUpdateService(
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
      versions['linux'],
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
    final archive = File('${dir.path}/knitcalc-update.tar.gz');
    await downloadFileWithControl(
      client: _httpClient,
      url: Uri.parse(url),
      dest: archive,
      onProgress: onProgress,
      control: control,
    );

    final executable = _executablePath;
    final script = buildLinuxUpdateScript(
      pid: pid,
      archivePath: archive.path,
      installDir: File(executable).parent.path,
      executablePath: executable,
    );

    // Hands off to the detached script and quits the app so it can swap the
    // bundle; control does not return here on the default launcher.
    await _launch(script);
  }
}

/// Writes the updater script to a temp file, launches it detached, and exits so
/// the script can replace the running bundle.
Future<void> _defaultLaunch(String scriptText) async {
  final dir = await getTemporaryDirectory();
  final script = File('${dir.path}/knitcalc-update.sh');
  await script.writeAsString(scriptText);

  await Process.start('/bin/sh', [
    script.path,
  ], mode: ProcessStartMode.detached);

  exit(0);
}
