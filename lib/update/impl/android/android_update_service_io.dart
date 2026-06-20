import 'dart:io';

import 'package:flutter/services.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
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

/// Supplies the device's primary ABI (e.g. `arm64-v8a`), or `null` when it
/// can't be determined — then the universal APK is used. Injected for tests.
typedef AbiProvider = Future<String?> Function();

/// Default [AbiProvider]: asks the platform for `Build.SUPPORTED_ABIS[0]`.
Future<String?> _primaryAbi() async {
  try {
    return await androidUpdateChannel.invokeMethod<String>('primaryAbi');
  } on PlatformException {
    return null;
  }
}

/// Sideload updater for APKs distributed via GitHub Releases.
///
/// Reads the available version from the remote store-versions document (the
/// `android` entry carries the APK download url, written by release CI),
/// downloads the APK to the cache directory (reporting progress) and hands it to
/// the system installer (the user confirms the install and the "unknown sources"
/// prompt if needed). The APK still downloads from the GitHub CDN; only the
/// version check moved off the GitHub API — its 60/hour unauthenticated limit is
/// shared per IP and easily exhausted under carrier-grade NAT on mobile.
class AndroidUpdateService implements UpdateService {
  AndroidUpdateService(
    this._current, {
    HttpClient? httpClient,
    RemoteVersionsFetcher? fetch,
    AbiProvider? abi,
  }) : _httpClient = httpClient ?? HttpClient(),
       _fetch = fetch ?? fetchStoreVersions,
       _abi = abi ?? _primaryAbi;

  final AppVersion? _current;
  final HttpClient _httpClient;
  final RemoteVersionsFetcher _fetch;
  final AbiProvider _abi;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final versions = await _fetch();
    final entry = versions['android'];

    // Prefer the device-ABI APK (~3x smaller) over the universal one; fall back
    // to the universal url/size when the ABI is unknown or has no variant.
    final asset = entry?.assetForAbi(await _abi());

    return evaluateRemoteUpdate(
      _current,
      entry,
      action: UpdateAction.inApp,
      url: asset?.url,
      downloadSize: asset?.size,
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

    final path = await _downloadApk(url, onProgress);

    await androidUpdateChannel.invokeMethod<void>('installApk', {'path': path});
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
