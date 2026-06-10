import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// Matches the Package field of packaging/apt/control, shipped in the apt repo
// the publish workflow renders under GitHub Pages (/knitcalc/apt).
const String aptPackage = 'knitcalc';

/// apt/dpkg updater spec. `apt-get -s install --only-upgrade` simulates the
/// upgrade (no root needed) to see whether a newer version is in the cache; the
/// real upgrade runs `sudo apt-get install --only-upgrade <pkg>` in a terminal.
///
/// Note: the result reflects the local apt cache, which may be stale without a
/// recent `apt update` (that needs root and is left to the user/system).
PackageManagerSpec aptSpec({String package = aptPackage}) => PackageManagerSpec(
  displayName: 'apt',
  packageId: package,
  executable: 'apt-get',
  probeArgs: ['-s', 'install', '--only-upgrade', package],
  upgradeCommand: ['sudo', 'apt-get', 'install', '--only-upgrade', package],
  parseAvailableVersion: (stdout) => parseAptSimulate(stdout, package: package),
);

/// Reads the candidate version from `apt-get -s install --only-upgrade` output.
///
/// A pending upgrade prints `Inst pkg [old] (new origin …)`; we pull the
/// version from inside the parentheses. `pkg is already the newest version`
/// (no `Inst` line) → `null`.
String? parseAptSimulate(String stdout, {required String package}) {
  final pattern = RegExp(
    '^Inst ${RegExp.escape(package)} .*?\\((\\S+)',
    multiLine: true,
  );

  return pattern.firstMatch(stdout)?.group(1);
}
