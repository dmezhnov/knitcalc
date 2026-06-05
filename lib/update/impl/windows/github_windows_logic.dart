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

/// Builds the detached PowerShell script that applies a downloaded Windows
/// bundle.
///
/// The app must quit after spawning it: Windows keeps the running executable
/// and its DLLs locked, so the script first waits for [pid] to disappear, then
/// unpacks [archivePath] over [installDir] (the bundle directory), removes the
/// archive and relaunches [executablePath]. The new build then sees its own
/// version on next launch.
///
/// Paths are emitted as single-quoted PowerShell literals (embedded quotes
/// doubled) so spaces in the install path are handled. CRLF line endings keep
/// the `.ps1` valid when written to disk on Windows.
String buildWindowsUpdateScript({
  required int pid,
  required String archivePath,
  required String installDir,
  required String executablePath,
}) {
  String literal(String value) => "'${value.replaceAll("'", "''")}'";

  return '# KnitCalc self-update: wait for the running app to exit, unpack the\r\n'
      '# new bundle over the install directory, then relaunch.\r\n'
      r'$ErrorActionPreference = "Stop"'
      '\r\n'
      'while (Get-Process -Id $pid -ErrorAction SilentlyContinue) {\r\n'
      '  Start-Sleep -Milliseconds 200\r\n'
      '}\r\n'
      'Expand-Archive -LiteralPath ${literal(archivePath)} '
      '-DestinationPath ${literal(installDir)} -Force\r\n'
      'Remove-Item -LiteralPath ${literal(archivePath)} -Force\r\n'
      'Start-Process -FilePath ${literal(executablePath)}\r\n';
}
