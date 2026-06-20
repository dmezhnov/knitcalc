import 'dart:io';

import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/macos/macos_swap_logic.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:path_provider/path_provider.dart';

/// Spawns the detached updater and terminates the app. Injectable for tests.
typedef UpdateLauncher = Future<void> Function(String scriptText);

UpdateService createMacosUpdateService(AppVersion? current) {
  // Only a real macOS desktop swaps its own bundle; other dart:io targets
  // (Linux/Windows builds of this factory) stay no-op.
  if (!Platform.isMacOS) {
    return const NoopUpdateService();
  }

  return MacosUpdateService(current);
}

/// Self-updater for manually installed macOS app bundles distributed as the
/// `knitcalc-macos-*.zip` GitHub Release asset.
///
/// Reads the available version from the remote store-versions document (the
/// `macos` entry carries the download url, written by release CI), downloads the
/// zip (reporting progress) and hands off to a detached shell script that
/// replaces the `.app` bundle once the app exits, then relaunches. Mac App Store
/// installs are handled by a [NoopUpdateService] instead — the store owns
/// updates there. The zip still downloads from the GitHub CDN; only the version
/// check moved off the rate-limited GitHub API.
class MacosUpdateService implements UpdateService {
  MacosUpdateService(
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
      versions['macos'],
      action: UpdateAction.inApp,
    );
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

    final appBundle = macAppBundlePath(_executablePath);

    final dir = await getTemporaryDirectory();
    final script = buildMacosUpdateScript(
      pid: pid,
      archivePath: archive,
      stagingDir: '${dir.path}/knitcalc-update-staging',
      appBundlePath: appBundle,
    );

    // Hands off to the detached script and quits the app so it can swap the
    // bundle; control does not return here on the default launcher.
    await _launch(script);
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
          onProgress(DownloadProgress(received: received, total: total));
        }
      }
    } finally {
      await sink.close();
    }

    return file.path;
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
