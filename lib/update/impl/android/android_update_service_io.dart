import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/android/github_release_logic.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:path_provider/path_provider.dart';

/// Method channel shared with [MainActivity] for install-source detection and
/// launching the package installer.
const MethodChannel androidUpdateChannel = MethodChannel(
  'knitcalc/android_update',
);

UpdateService createAndroidUpdateService(AppVersion? current) {
  // Only Android can install an APK; other dart:io targets stay no-op.
  if (!Platform.isAndroid) {
    return const NoopUpdateService();
  }

  return AndroidUpdateService(current);
}

/// Sideload updater for APKs distributed via GitHub Releases.
///
/// Polls `releases/latest`, compares the tag with the running build, downloads
/// the APK to the cache directory (reporting progress) and hands it to the
/// system installer (the user confirms the install and the "unknown sources"
/// prompt if needed).
class AndroidUpdateService implements UpdateService {
  AndroidUpdateService(this._current, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final AppVersion? _current;
  final HttpClient _httpClient;

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

    return evaluateGithubApkUpdate(_current, release);
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

    final path = await _downloadApk(url, onProgress);

    await androidUpdateChannel.invokeMethod<void>('installApk', {'path': path});
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

  Future<String> _downloadApk(
    String url,
    UpdateProgressCallback? onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/knitcalc-update.apk');

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
