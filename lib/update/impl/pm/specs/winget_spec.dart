import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// TODO(update): replace with the real winget package id once published to
// winget-pkgs (placeholder, like com.example.knitcalc for iTunes Lookup).
const String wingetPackageId = 'Dmezhnov.KnitCalc';

/// winget updater spec. Probe is read-only; the upgrade runs `winget upgrade`
/// in a terminal (winget self-elevates via UAC when needed).
PackageManagerSpec wingetSpec({String packageId = wingetPackageId}) =>
    PackageManagerSpec(
      displayName: 'winget',
      packageId: packageId,
      executable: 'winget',
      probeArgs: ['upgrade', '--id', packageId, '--exact', '--include-unknown'],
      upgradeCommand: ['winget', 'upgrade', '--id', packageId, '--exact'],
      parseAvailableVersion: (stdout) =>
          parseWingetUpgrade(stdout, packageId: packageId),
    );

/// Reads the *Available* version from `winget upgrade --id <id>` output.
///
/// winget prints a column-aligned table; when an upgrade exists the row for the
/// package looks like `Name  <id>  <current>  <available>  <source>`. The data
/// columns (id, versions, source) never contain spaces and aren't localized, so
/// we take the second-to-last whitespace token of the package's row regardless
/// of locale or a name with spaces. Returns `null` when no such row is present
/// ("No available upgrade found." / "No installed package found …").
String? parseWingetUpgrade(String stdout, {required String packageId}) {
  for (final line in stdout.split('\n')) {
    final tokens = line.trim().split(RegExp(r'\s+'));

    // Name(>=1) + Id + Version + Available + Source → at least 5 tokens, and
    // the row must carry the exact package id.
    if (tokens.length < 5 || !tokens.contains(packageId)) {
      continue;
    }

    final available = tokens[tokens.length - 2];

    if (RegExp(r'^\d').hasMatch(available)) {
      return available;
    }
  }

  return null;
}
