/// Pure decoding and evaluation of the remote "store versions" document.
///
/// A single Firestore document (`config/storeVersions`) is the source of truth
/// for update availability across every channel that used to poll the GitHub
/// API. Keeping the check off GitHub avoids the unauthenticated rate limit
/// (60 requests/hour per IP — easily shared away under carrier-grade NAT on
/// mobile) and, for store channels, lets the version be bumped only once the
/// store has actually published — so the banner never runs ahead of the store.
///
/// Each field is keyed by channel (`android`, `windows`, `macos`, `linux`,
/// `samsung`, `amazon`, `huawei`, `fdroid`, `accrescent`). A value is either:
///   - a bare version string (`{"stringValue": "1.8.34+57"}`) — used for store
///     channels, where the app only needs to know the version and opens the
///     listing to update; or
///   - a map (`{"mapValue": {"fields": {version, url, size, notes}}}`) — used
///     for the self-update channels, which download `url` and install it.
///
/// Firestore's REST API tags every value (`stringValue`, `integerValue`,
/// `mapValue`, …); these helpers translate that shape, like firestore_codec.
library;

import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_info.dart';

/// Document path of the public store-versions config.
const String storeVersionsDocumentPath = 'config/storeVersions';

/// A downloadable asset (URL + optional byte size).
class RemoteAsset {
  const RemoteAsset({required this.url, this.size});

  final String url;
  final int? size;
}

/// One channel's entry in the store-versions document.
class RemoteEntry {
  const RemoteEntry({
    required this.version,
    required this.label,
    this.url,
    this.size,
    this.notes,
    this.abis = const {},
  });

  /// Parsed version available in the channel's source.
  final AppVersion version;

  /// Human-readable version for the banner (the raw string as published).
  final String label;

  /// Download URL for self-update channels; `null` for store-listing channels.
  /// For Android this is the universal APK — the all-ABI fallback.
  final String? url;

  /// Payload size in bytes, when present.
  final int? size;

  /// Release notes, when present.
  final String? notes;

  /// Per-ABI download variants keyed by Android ABI (e.g. `arm64-v8a`), when the
  /// channel publishes split APKs. Empty for channels that don't. The much
  /// smaller per-ABI APK is preferred over the universal [url] when the running
  /// device's ABI matches.
  final Map<String, RemoteAsset> abis;

  /// The best download for [abi]: the matching per-ABI variant, or `null` to
  /// fall back to the universal [url]/[size].
  RemoteAsset? assetForAbi(String? abi) => abi == null ? null : abis[abi];
}

/// REST URL of the public store-versions document. Read is unauthenticated —
/// the API key (shipped in the app) plus a public read rule on `config/{doc}`
/// are enough; no id token, so it works before/without sign-in.
Uri storeVersionsUrl(FirebaseConfig config) => Uri.parse(
  'https://firestore.googleapis.com/v1/projects/${config.projectId}'
  '/databases/(default)/documents/$storeVersionsDocumentPath'
  '?key=${config.apiKey}',
);

/// Decodes a Firestore document (`{name, fields, ...}`) into channel entries.
///
/// Fields whose version cannot be parsed are skipped, so a malformed entry for
/// one channel never breaks the others.
Map<String, RemoteEntry> decodeStoreVersions(Map<String, dynamic> document) {
  final fields = document['fields'] as Map<String, dynamic>? ?? const {};
  final entries = <String, RemoteEntry>{};

  for (final field in fields.entries) {
    final value = field.value;

    if (value is! Map<String, dynamic>) {
      continue;
    }

    final entry = _decodeEntry(value);

    if (entry != null) {
      entries[field.key] = entry;
    }
  }

  return entries;
}

RemoteEntry? _decodeEntry(Map<String, dynamic> value) {
  // Bare string: a version with no download payload (store-listing channels).
  final asString = value['stringValue'];

  if (asString is String) {
    final version = AppVersion.tryParse(asString);

    return version == null
        ? null
        : RemoteEntry(version: version, label: asString);
  }

  // Map: a self-update channel carrying the download url/size/notes.
  final mapFields =
      value['mapValue']?['fields'] as Map<String, dynamic>? ?? const {};

  final rawVersion = mapFields['version']?['stringValue'];

  if (rawVersion is! String) {
    return null;
  }

  final version = AppVersion.tryParse(rawVersion);

  if (version == null) {
    return null;
  }

  final url = mapFields['url']?['stringValue'];
  final notes = mapFields['notes']?['stringValue'];
  // integerValue arrives as a decimal string per the REST encoding.
  final size = int.tryParse(
    mapFields['size']?['integerValue']?.toString() ?? '',
  );

  return RemoteEntry(
    version: version,
    label: rawVersion,
    url: url is String ? url : null,
    size: size,
    notes: notes is String && notes.isNotEmpty ? notes : null,
    abis: _decodeAbis(mapFields['abis']),
  );
}

/// Decodes the optional per-ABI variants sub-map
/// (`abis.mapValue.fields.<abi>.mapValue.fields.{url,size}`). Entries without a
/// url are skipped so a malformed variant never breaks the others.
Map<String, RemoteAsset> _decodeAbis(dynamic abis) {
  final fields =
      abis?['mapValue']?['fields'] as Map<String, dynamic>? ?? const {};
  final result = <String, RemoteAsset>{};

  for (final field in fields.entries) {
    final assetFields =
        field.value?['mapValue']?['fields'] as Map<String, dynamic>?;
    final url = assetFields?['url']?['stringValue'];

    if (url is! String) {
      continue;
    }

    result[field.key] = RemoteAsset(
      url: url,
      size: int.tryParse(
        assetFields?['size']?['integerValue']?.toString() ?? '',
      ),
    );
  }

  return result;
}

/// Builds an [UpdateInfo] for [entry] when it is newer than [current].
///
/// Returns `null` when the running version is unknown, there is no entry, or it
/// is not newer. [action] is the delivery (in-app download vs. open the store
/// listing); [url] overrides the entry's url — store channels pass the listing
/// link, self-update channels leave it null to use the entry's download url.
/// [downloadSize] overrides the entry's size, e.g. when a per-ABI asset (with
/// its own size) is chosen over the universal one.
UpdateInfo? evaluateRemoteUpdate(
  AppVersion? current,
  RemoteEntry? entry, {
  required UpdateAction action,
  String? url,
  int? downloadSize,
}) {
  if (current == null || entry == null) {
    return null;
  }

  if (!current.isOlderThan(entry.version)) {
    return null;
  }

  return UpdateInfo(
    latestVersion: entry.version,
    versionLabel: entry.label,
    action: action,
    url: url ?? entry.url,
    downloadSize: downloadSize ?? entry.size,
    releaseNotes: entry.notes,
  );
}
