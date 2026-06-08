import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// TODO(update): confirm the published snap name (matches snap/snapcraft.yaml).
const String snapName = 'knitcalc';

/// snap updater spec. `snap refresh --list` shows snaps with a pending refresh;
/// the upgrade runs `sudo snap refresh <name>` in a terminal (refresh needs
/// root, so the user answers the sudo prompt there).
PackageManagerSpec snapSpec({String name = snapName}) => PackageManagerSpec(
  displayName: 'snap',
  packageId: name,
  executable: 'snap',
  probeArgs: ['refresh', '--list'],
  upgradeCommand: ['sudo', 'snap', 'refresh', name],
  parseAvailableVersion: (stdout) => parseSnapRefreshList(stdout, name: name),
);

/// Reads the available version from `snap refresh --list` output.
///
/// The table is `Name  Version  Rev  Publisher  Notes`; we find the row whose
/// first token is [name] and take the second token (Version). "All snaps up to
/// date." (or no matching row) → `null`.
String? parseSnapRefreshList(String stdout, {required String name}) {
  for (final line in stdout.split('\n')) {
    final tokens = line.trim().split(RegExp(r'\s+'));

    if (tokens.length < 2 || tokens.first != name) {
      continue;
    }

    final version = tokens[1];

    // Skip the header row whose second column is the literal "Version".
    return version == 'Version' ? null : version;
  }

  return null;
}
