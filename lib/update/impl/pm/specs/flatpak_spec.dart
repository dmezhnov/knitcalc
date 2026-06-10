import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// Matches `id` in packaging/flatpak/flatpak-flutter.yml (the Flathub
// submission) and APPLICATION_ID in linux/CMakeLists.txt.
const String flatpakAppId = 'io.github.dmezhnov.knitcalc';

/// flatpak updater spec. `flatpak remote-ls --updates` lists apps with a newer
/// version available; the upgrade runs `flatpak update <app-id>` in a terminal
/// (flatpak prompts the user to confirm, no root needed for a user install).
PackageManagerSpec flatpakSpec({String appId = flatpakAppId}) =>
    PackageManagerSpec(
      displayName: 'flatpak',
      packageId: appId,
      executable: 'flatpak',
      probeArgs: [
        'remote-ls',
        '--updates',
        '--app',
        '--columns=application,version',
      ],
      upgradeCommand: ['flatpak', 'update', appId],
      parseAvailableVersion: (stdout) =>
          parseFlatpakUpdates(stdout, appId: appId),
    );

/// Reads the available version from `flatpak remote-ls --updates` output.
///
/// Each line is `<application>\t<version>` (or space-separated); we find the
/// row for [appId] and take its last whitespace token as the version. Empty
/// output means up to date → `null`.
String? parseFlatpakUpdates(String stdout, {required String appId}) {
  for (final line in stdout.split('\n')) {
    final tokens = line.trim().split(RegExp(r'\s+'));

    if (tokens.length < 2 || tokens.first != appId) {
      continue;
    }

    final version = tokens.last;

    return version.isNotEmpty ? version : null;
  }

  return null;
}
