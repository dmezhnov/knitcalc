import 'dart:convert';
import 'dart:io';

import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/github/github_release.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/windows/github_windows_logic.dart';
import 'package:knitcalc/update/update_info.dart';
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
/// Polls `releases/latest`, compares the tag with the running build, downloads
/// the zip (reporting progress) and hands off to the bundled updater helper
/// ([updaterExecutable]): the app copies the helper to a temp dir, spawns it
/// detached with the running pid, and quits; the helper waits for the app to
/// exit (so the bundle's files unlock), unpacks the zip over the install
/// directory and relaunches. This works on both native Windows and Wine/Proton
/// — neither lets a running process replace its own open files. Microsoft Store
/// (MSIX) installs are handled by a [NoopUpdateService] instead.
class WindowsUpdateService implements UpdateService {
  WindowsUpdateService(
    this._current, {
    HttpClient? httpClient,
    UpdateLauncher? launch,
  }) : _httpClient = httpClient ?? HttpClient(),
       _launch = launch ?? _defaultLaunch;

  final AppVersion? _current;
  final HttpClient _httpClient;
  final UpdateLauncher _launch;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    if (_current == null) {
      return null;
    }

    final Map<String, dynamic> release;

    try {
      release = await _fetchLatestRelease();
    } on Object {
      // Offline or rate-limited: skip silently, retry next launch.
      return null;
    }

    return evaluateGithubWindowsUpdate(_current, release);
  }

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
  }) async {
    final url = info.url;

    if (url == null) {
      return;
    }

    final archive = await _downloadArchive(url, onProgress);

    final executable = Platform.resolvedExecutable;
    final installDir = File(executable).parent.path;

    // Hands off to the detached helper and quits the app so it can swap the
    // bundle; control does not return here on the default launcher.
    await _launch(archive, installDir, executable);
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final request = await _httpClient.getUrl(Uri.parse(githubLatestReleaseUrl));
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'knitcalc-updater');

    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Unexpected status ${response.statusCode}');
    }

    final body = await response.transform(utf8.decoder).join();

    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<String> _downloadArchive(
    String url,
    UpdateProgressCallback? onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/knitcalc-update.zip');

    final request = await _httpClient.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, 'knitcalc-updater');

    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Download failed with status ${response.statusCode}');
    }

    // contentLength is -1 when the server omits it; progress then stays
    // indeterminate and the UI shows a spinner instead of a percentage.
    final total = response.contentLength;
    final sink = file.openWrite();
    var received = 0;

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;

        if (onProgress != null && total > 0) {
          onProgress(received / total);
        }
      }
    } finally {
      await sink.close();
    }

    return file.path;
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
