import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/github/github_release.dart';
import 'package:knitcalc/update/update_info.dart';

/// Matches the Linux x64 bundle tarball, e.g. `knitcalc-linux-x64-1.4.1+4.tar.gz`.
///
/// The `linux` segment keeps the web bundle (`knitcalc-web-*.tar.gz`) from being
/// picked up.
bool isLinuxTarballAsset(String name) {
  final lower = name.toLowerCase();

  return lower.contains('linux') && lower.endsWith('.tar.gz');
}

/// Picks the Linux tarball asset from a GitHub release payload, or `null`.
ReleaseAsset? findLinuxTarballAsset(Map<String, dynamic> releaseJson) =>
    findReleaseAsset(releaseJson, isLinuxTarballAsset);

/// Builds an [UpdateInfo] from a GitHub `releases/latest` payload for the Linux
/// manual (tarball) channel. Returns `null` when there is nothing newer to
/// install (see [evaluateGithubUpdate]).
UpdateInfo? evaluateGithubTarballUpdate(
  AppVersion? current,
  Map<String, dynamic> releaseJson,
) => evaluateGithubUpdate(
  current,
  releaseJson,
  assetMatches: isLinuxTarballAsset,
);

/// Builds the detached `/bin/sh` script that applies a downloaded Linux bundle.
///
/// The app must quit after spawning it: the script waits for [pid] to disappear
/// (so the running executable is no longer busy), unpacks [archivePath] over
/// [installDir] (the bundle directory), removes the archive and relaunches
/// [executablePath]. The new build then sees its own version on next launch.
String buildLinuxUpdateScript({
  required int pid,
  required String archivePath,
  required String installDir,
  required String executablePath,
}) =>
    '#!/bin/sh\n'
    '# KnitCalc self-update: wait for the running app to exit, unpack the new\n'
    '# bundle over the install directory, then relaunch.\n'
    'set -e\n'
    'while kill -0 $pid 2>/dev/null; do\n'
    '  sleep 0.2\n'
    'done\n'
    'tar -xzf "$archivePath" -C "$installDir"\n'
    'rm -f "$archivePath"\n'
    'exec "$executablePath"\n';
