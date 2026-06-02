import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_info.dart';

/// GitHub `releases/latest` endpoint for the sideload (GitHub APK) channel.
const String githubLatestReleaseUrl =
    'https://api.github.com/repos/dmezhnov/knitcalc/releases/latest';

/// A single downloadable artifact attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}

/// Picks the APK asset from a GitHub release payload, ignoring the `.aab`
/// bundle and every other platform's artifact. Returns `null` when none is
/// present.
ReleaseAsset? findApkAsset(Map<String, dynamic> releaseJson) {
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

    if (name is String &&
        url is String &&
        name.toLowerCase().endsWith('.apk')) {
      return ReleaseAsset(name: name, downloadUrl: url);
    }
  }

  return null;
}

/// Builds an [UpdateInfo] from a GitHub `releases/latest` payload.
///
/// Returns `null` when the running [current] version is unknown, the release
/// tag cannot be parsed, the release is not newer, or it carries no APK asset
/// to install.
UpdateInfo? evaluateGithubApkUpdate(
  AppVersion? current,
  Map<String, dynamic> releaseJson,
) {
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

  final apk = findApkAsset(releaseJson);

  if (apk == null) {
    return null;
  }

  final notes = releaseJson['body'];

  return UpdateInfo(
    latestVersion: latest,
    action: UpdateAction.inApp,
    url: apk.downloadUrl,
    releaseNotes: notes is String && notes.isNotEmpty ? notes : null,
  );
}
