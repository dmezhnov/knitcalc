import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/github/github_release.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/windows/github_windows_logic.dart';
import 'package:knitcalc/update/impl/windows/wine_update_logic.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:path_provider/path_provider.dart';

/// Spawns the detached PowerShell updater and terminates the app (native Windows
/// path). Injectable for tests.
typedef UpdateLauncher = Future<void> Function(String scriptText);

/// Applies the bundle in-process and relaunches (Wine/Proton path). Injectable
/// for tests.
typedef WineApplier =
    Future<void> Function(
      String archivePath,
      String installDir,
      String executablePath,
    );

UpdateService createWindowsUpdateService(AppVersion? current) {
  // Only a real Windows desktop (incl. under Wine/Proton) swaps its own bundle;
  // other dart:io targets (Linux/macOS builds of this factory) stay no-op.
  if (!Platform.isWindows) {
    return const NoopUpdateService();
  }

  return WindowsUpdateService(current);
}

/// Detects whether this Windows build is actually running under Wine/Proton.
///
/// Wine (and Proton, which is built on Wine) exposes a `wine_get_version` export
/// in `ntdll.dll` that native Windows lacks; its presence is the canonical
/// Wine/Proton marker. Used to pick the in-process update path, since Wine
/// prefixes ship no PowerShell to run the native updater script.
bool isRunningUnderWine() {
  if (!Platform.isWindows) {
    return false;
  }

  try {
    return DynamicLibrary.open('ntdll.dll').providesSymbol('wine_get_version');
  } on Object {
    return false;
  }
}

/// Self-updater for manually installed Windows bundles distributed as the
/// `knitcalc-windows-x64-*.zip` GitHub Release asset.
///
/// Polls `releases/latest`, compares the tag with the running build, downloads
/// the zip (reporting progress) and applies it. On native Windows it hands off
/// to a detached PowerShell script that unpacks the zip over the install
/// directory once the app exits, then relaunches. Under Wine/Proton there is no
/// file lock and no PowerShell, so it instead unpacks in-process and relaunches
/// directly. Microsoft Store (MSIX) installs are handled by a
/// [NoopUpdateService] instead — the store owns updates.
class WindowsUpdateService implements UpdateService {
  WindowsUpdateService(
    this._current, {
    HttpClient? httpClient,
    UpdateLauncher? launch,
    WineApplier? wineApply,
    bool? underWine,
  }) : _httpClient = httpClient ?? HttpClient(),
       _launch = launch ?? _defaultLaunch,
       _wineApply = wineApply ?? _defaultWineApply,
       _underWine = underWine ?? isRunningUnderWine();

  final AppVersion? _current;
  final HttpClient _httpClient;
  final UpdateLauncher _launch;
  final WineApplier _wineApply;
  final bool _underWine;

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

    if (_underWine) {
      // Wine/Proton: no file lock, no PowerShell. Swap the bundle in-process and
      // relaunch; control does not return here on the default applier.
      await _wineApply(archive, installDir, executable);
      return;
    }

    final script = buildWindowsUpdateScript(
      pid: pid,
      archivePath: archive,
      installDir: installDir,
      executablePath: executable,
    );

    // Hands off to the detached script and quits the app so it can swap the
    // bundle; control does not return here on the default launcher.
    await _launch(script);
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

/// Writes the updater script to a temp file, launches it detached via
/// PowerShell, and exits so the script can replace the running bundle (native
/// Windows path).
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

/// Unpacks the bundle over the install directory in-process and relaunches the
/// new executable, then exits (Wine/Proton path).
Future<void> _defaultWineApply(
  String archivePath,
  String installDir,
  String executablePath,
) async {
  applyZipOverDirectory(archivePath, installDir);

  await Process.start(
    executablePath,
    const [],
    mode: ProcessStartMode.detached,
  );

  exit(0);
}
