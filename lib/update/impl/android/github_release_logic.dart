import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/github/github_release.dart';
import 'package:knitcalc/update/update_info.dart';

// Re-exported so existing call sites and tests keep importing these from here.
export 'package:knitcalc/update/impl/github/github_release.dart'
    show ReleaseAsset, githubLatestReleaseUrl;

/// Matches the APK artifact, ignoring the `.aab` bundle and other platforms.
bool isApkAsset(String name) => name.toLowerCase().endsWith('.apk');

/// Picks the APK asset from a GitHub release payload. Returns `null` when none
/// is present.
ReleaseAsset? findApkAsset(Map<String, dynamic> releaseJson) =>
    findReleaseAsset(releaseJson, isApkAsset);

/// Builds an [UpdateInfo] from a GitHub `releases/latest` payload for the
/// sideload (APK) channel. Returns `null` when there is nothing newer to
/// install (see [evaluateGithubUpdate]).
UpdateInfo? evaluateGithubApkUpdate(
  AppVersion? current,
  Map<String, dynamic> releaseJson,
) => evaluateGithubUpdate(current, releaseJson, assetMatches: isApkAsset);
