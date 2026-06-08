import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/store/itunes_lookup.dart';
import 'package:knitcalc/update/impl/store/store_launch.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// Returns the App Store update service for the running build.
UpdateService createIosAppStoreService(AppVersion? current) =>
    IosAppStoreService(current: current);

/// Update service for App Store builds.
///
/// Asks the iTunes Lookup API for the version currently live on the store (so
/// it never announces a release the store has not approved yet) and, on update,
/// opens the App Store listing — the store ships the actual binary.
class IosAppStoreService implements UpdateService {
  IosAppStoreService({
    required AppVersion? current,
    String bundleId = appBundleId,
    String? country,
    http.Client? httpClient,
    UrlLauncher? launchUrl,
  }) : _current = current,
       _bundleId = bundleId,
       _country = country,
       _httpClient = httpClient ?? http.Client(),
       _launch = launchUrl ?? launchExternal;

  final AppVersion? _current;
  final String _bundleId;
  final String? _country;
  final http.Client _httpClient;
  final UrlLauncher _launch;

  /// Links from the last successful lookup, deep link first; [startUpdate]
  /// opens them in order.
  List<Uri> _launchUrls = const [];

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    if (_current == null) {
      return null;
    }

    final Map<String, dynamic> json;

    try {
      json = await _fetchLookup();
    } on Object {
      // Offline or unexpected payload: skip silently, retry next launch.
      return null;
    }

    final info = evaluateItunesUpdate(_current, json);

    if (info == null) {
      return null;
    }

    // parseItunesLookup already succeeded inside evaluateItunesUpdate; recompute
    // the launch links from the same payload for startUpdate.
    _launchUrls = appStoreUrls(parseItunesLookup(json)!);

    return info;
  }

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
  }) async {
    final urls = _launchUrls.isNotEmpty
        ? _launchUrls
        : [if (info.url != null) Uri.parse(info.url!)];

    if (!await launchFirstAvailable(urls, _launch)) {
      throw StateError('Could not open the App Store listing: $urls');
    }
  }

  Future<Map<String, dynamic>> _fetchLookup() async {
    final response = await _httpClient.get(
      itunesLookupUrl(_bundleId, country: _country),
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw http.ClientException('Unexpected status ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
