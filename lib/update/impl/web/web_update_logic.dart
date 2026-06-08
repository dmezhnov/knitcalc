import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_info.dart';

/// Reads the version advertised by Flutter's generated `version.json`.
///
/// The file looks like `{"version":"1.2.0","build_number":"1", ...}`. The
/// build number, when present, becomes the `+build` tie-breaker. Returns null
/// when the payload lacks a usable version string.
AppVersion? parseDeployedVersion(Map<String, dynamic> versionJson) {
  final version = versionJson['version'];
  if (version is! String || version.isEmpty) {
    return null;
  }

  final build = versionJson['build_number'];
  final suffix = build is String && build.isNotEmpty ? '+$build' : '';

  return AppVersion.tryParse('$version$suffix');
}

/// Decides whether a freshly fetched `version.json` describes a newer build
/// than the one currently running.
///
/// Returns the update to offer, or null when [current] is unknown, the payload
/// is unparsable, or the deployment is not newer than [current].
UpdateInfo? evaluateWebUpdate(
  AppVersion? current,
  Map<String, dynamic> versionJson,
) {
  if (current == null) {
    return null;
  }

  final deployed = parseDeployedVersion(versionJson);
  if (deployed == null || !current.isOlderThan(deployed)) {
    return null;
  }

  return UpdateInfo(
    latestVersion: deployed,
    action: UpdateAction.inApp,
    versionLabel: deployed.toString(),
  );
}
