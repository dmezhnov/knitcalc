import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/github/github_release.dart';
import 'package:knitcalc/update/update_info.dart';

/// Matches the Windows x64 bundle zip, e.g. `knitcalc-windows-x64-1.4.2+8.zip`.
///
/// The `windows` segment keeps the other zip assets (macOS/iOS .zip bundles)
/// from being picked up.
bool isWindowsZipAsset(String name) {
  final lower = name.toLowerCase();

  return lower.contains('windows') && lower.endsWith('.zip');
}

/// Picks the Windows zip asset from a GitHub release payload, or `null`.
ReleaseAsset? findWindowsZipAsset(Map<String, dynamic> releaseJson) =>
    findReleaseAsset(releaseJson, isWindowsZipAsset);

/// Builds an [UpdateInfo] from a GitHub `releases/latest` payload for the
/// Windows manual (zip) channel. Returns `null` when there is nothing newer to
/// install (see [evaluateGithubUpdate]).
UpdateInfo? evaluateGithubWindowsUpdate(
  AppVersion? current,
  Map<String, dynamic> releaseJson,
) =>
    evaluateGithubUpdate(current, releaseJson, assetMatches: isWindowsZipAsset);
