import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// TODO(update): confirm the published Chocolatey package id (matches
// packaging/chocolatey/knitcalc.nuspec).
const String chocolateyPackageId = 'knitcalc';

/// Chocolatey updater spec. The probe uses machine-readable output:
/// `choco outdated -r` prints one `name|installed|available|pinned` line per
/// outdated package. Unlike winget, `choco upgrade` does not self-elevate; if
/// the terminal is not admin, choco prints a clear "run elevated" error and
/// the window stays open so the user can rerun it as administrator.
PackageManagerSpec chocolateySpec({String packageId = chocolateyPackageId}) =>
    PackageManagerSpec(
      displayName: 'Chocolatey',
      packageId: packageId,
      executable: 'choco',
      probeArgs: ['outdated', '-r'],
      upgradeCommand: ['choco', 'upgrade', packageId, '-y'],
      parseAvailableVersion: (stdout) =>
          parseChocoOutdated(stdout, packageId: packageId),
    );

/// Reads the *available* field of the package's `choco outdated -r` line.
///
/// Returns `null` when the package is absent from the list (up to date or not
/// installed through Chocolatey) or pinned — a pin is the user explicitly
/// opting out of upgrades, so the banner must not nag about one.
String? parseChocoOutdated(String stdout, {required String packageId}) {
  for (final line in stdout.split('\n')) {
    final fields = line.trim().split('|');

    if (fields.length < 4 || fields[0] != packageId) {
      continue;
    }

    if (fields[3].toLowerCase().startsWith('true')) {
      return null;
    }

    final available = fields[2];

    if (RegExp(r'^\d').hasMatch(available)) {
      return available;
    }
  }

  return null;
}
