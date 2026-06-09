import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// The Scoop app name matches bucket/knitcalc.json, which the release workflow
// renders from packaging/scoop/ (the app repo itself serves as the bucket).
const String scoopAppName = 'knitcalc';

/// Scoop updater spec. `scoop` is a PowerShell script behind a `scoop.cmd`
/// shim that `Process.run` cannot spawn directly, so the probe goes through
/// `cmd /c` (the upgrade already runs inside a `cmd /k` terminal, which
/// resolves the shim itself). `scoop status` checks remote buckets by default
/// in current Scoop, so the probe sees updates without a prior `scoop update`.
PackageManagerSpec scoopSpec({String appName = scoopAppName}) =>
    PackageManagerSpec(
      displayName: 'Scoop',
      packageId: appName,
      executable: 'cmd',
      probeArgs: ['/c', 'scoop', 'status'],
      upgradeCommand: ['scoop', 'update', appName],
      parseAvailableVersion: (stdout) =>
          parseScoopStatus(stdout, appName: appName),
    );

/// Reads the *Latest Version* column from `scoop status` output.
///
/// `scoop status` lists only apps that need attention, in a column-aligned
/// table (`Name  Installed Version  Latest Version  Missing Dependencies
/// Info`). The app's row is matched by its first token; the third token is the
/// latest version when an update is on offer. Rows where the latest-version
/// column is empty (held package, failed install — the Info text shifts into
/// the third token) don't start with a digit and are rejected, as is output
/// with no row for the app ("Everything is ok!").
String? parseScoopStatus(String stdout, {required String appName}) {
  for (final line in stdout.split('\n')) {
    final tokens = line.trim().split(RegExp(r'\s+'));

    if (tokens.length < 3 || tokens[0] != appName) {
      continue;
    }

    final latest = tokens[2];

    if (RegExp(r'^\d').hasMatch(latest)) {
      return latest;
    }
  }

  return null;
}
