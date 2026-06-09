import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_info.dart';

/// App bundle identifier the App Store listing is keyed by. Matches the iOS
/// PRODUCT_BUNDLE_IDENTIFIER; the lookup only resolves once the app is actually
/// published to the App Store under this id.
const String appBundleId = 'io.github.dmezhnov.knitcalc';

/// iTunes Lookup endpoint that returns the version currently live on the App
/// Store for [bundleId] — the source of truth that avoids the store-review lag
/// of comparing against a freshly cut GitHub release.
///
/// The App Store is region-partitioned; [country] (ISO code, e.g. `ru`) scopes
/// the lookup to that storefront when given.
Uri itunesLookupUrl(String bundleId, {String? country}) {
  final params = {'bundleId': bundleId, 'country': ?country};

  return Uri.https('itunes.apple.com', '/lookup', params);
}

/// The fields we use from a single iTunes Lookup result.
class ItunesResult {
  const ItunesResult({required this.version, this.trackId, this.trackViewUrl});

  /// Marketing version live on the App Store (CFBundleShortVersionString).
  final String version;

  /// Numeric App Store id, used to build the `itms-apps://` deep link.
  final int? trackId;

  /// Canonical https listing URL, used as the fallback link.
  final String? trackViewUrl;
}

/// Parses an iTunes Lookup payload, returning the first result or `null` when
/// the app is not on the store (`resultCount` 0) or the payload is malformed.
ItunesResult? parseItunesLookup(Map<String, dynamic> json) {
  final results = json['results'];

  if (results is! List || results.isEmpty) {
    return null;
  }

  final first = results.first;

  if (first is! Map) {
    return null;
  }

  final version = first['version'];

  if (version is! String || version.isEmpty) {
    return null;
  }

  final trackId = first['trackId'];
  final trackViewUrl = first['trackViewUrl'];

  return ItunesResult(
    version: version,
    trackId: trackId is int ? trackId : null,
    trackViewUrl: trackViewUrl is String ? trackViewUrl : null,
  );
}

/// App Store links for [result], most-preferred first: the `itms-apps://` deep
/// link (opens the App Store app straight on the listing) then the https
/// fallback. Empty when neither a track id nor a listing URL is present.
List<Uri> appStoreUrls(ItunesResult result) {
  return [
    if (result.trackId != null)
      Uri.parse('itms-apps://itunes.apple.com/app/id${result.trackId}'),
    if (result.trackViewUrl != null) Uri.parse(result.trackViewUrl!),
  ];
}

/// Builds an [UpdateInfo] from an iTunes Lookup payload: the App Store ships the
/// binary, so the action is [UpdateAction.openUrl] pointing at the listing.
///
/// Returns `null` when [current] is unknown, the app is not on the store, the
/// version cannot be parsed, the live version is not newer, or no link exists.
UpdateInfo? evaluateItunesUpdate(
  AppVersion? current,
  Map<String, dynamic> json,
) {
  if (current == null) {
    return null;
  }

  final result = parseItunesLookup(json);

  if (result == null) {
    return null;
  }

  final latest = AppVersion.tryParse(result.version);

  if (latest == null || !current.isOlderThan(latest)) {
    return null;
  }

  final urls = appStoreUrls(result);

  if (urls.isEmpty) {
    return null;
  }

  return UpdateInfo(
    latestVersion: latest,
    action: UpdateAction.openUrl,
    versionLabel: result.version,
    // The https listing is the human-readable reference; startUpdate prefers
    // the deep link at launch time.
    url: urls.last.toString(),
  );
}
