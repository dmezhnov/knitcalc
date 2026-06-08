import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_info.dart';

/// GitHub `releases/latest` endpoint shared by the channels that self-update
/// from GitHub Releases (Android sideload, Linux manual installs).
const String githubLatestReleaseUrl =
    'https://api.github.com/repos/dmezhnov/knitcalc/releases/latest';

/// A single downloadable artifact attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.sizeInBytes,
  });

  final String name;
  final String downloadUrl;

  /// Artifact size in bytes from the release payload's `size` field, or `null`
  /// when it is absent or malformed.
  final int? sizeInBytes;
}

/// Returns the first release asset whose name satisfies [matches], or `null`
/// when the payload carries no matching artifact.
ReleaseAsset? findReleaseAsset(
  Map<String, dynamic> releaseJson,
  bool Function(String name) matches,
) {
  final assets = releaseJson['assets'];

  if (assets is! List) {
    return null;
  }

  for (final asset in assets) {
    if (asset is! Map) {
      continue;
    }

    final name = asset['name'];
    final url = asset['browser_download_url'];
    final size = asset['size'];

    if (name is String && url is String && matches(name)) {
      return ReleaseAsset(
        name: name,
        downloadUrl: url,
        sizeInBytes: size is int ? size : null,
      );
    }
  }

  return null;
}

/// Builds an [UpdateInfo] from a GitHub `releases/latest` payload, selecting the
/// artifact with [assetMatches].
///
/// Returns `null` when the running [current] version is unknown, the release
/// tag cannot be parsed, the release is not newer, or it carries no matching
/// asset to install.
UpdateInfo? evaluateGithubUpdate(
  AppVersion? current,
  Map<String, dynamic> releaseJson, {
  required bool Function(String name) assetMatches,
}) {
  if (current == null) {
    return null;
  }

  final tag = releaseJson['tag_name'];

  if (tag is! String) {
    return null;
  }

  final latest = AppVersion.tryParse(tag);

  if (latest == null || !current.isOlderThan(latest)) {
    return null;
  }

  final asset = findReleaseAsset(releaseJson, assetMatches);

  if (asset == null) {
    return null;
  }

  final notes = releaseJson['body'];

  return UpdateInfo(
    latestVersion: latest,
    action: UpdateAction.inApp,
    versionLabel: latest.toString(),
    url: asset.downloadUrl,
    downloadSize: asset.sizeInBytes,
    releaseNotes: notes is String && notes.isNotEmpty ? notes : null,
  );
}
