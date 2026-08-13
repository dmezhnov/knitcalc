import 'dart:convert';

import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// Tool name under which mise knows the app: the id of the registry entry
// rendered into packaging/mise/knitcalc.toml, and the alias the pre-registry
// install instructions use (see packaging/README.md), so both installs answer
// to `mise upgrade knitcalc`.
const String miseToolName = 'knitcalc';

/// mise updater spec. `mise outdated --json` lists the tools that have a newer
/// version; the upgrade runs `mise upgrade <tool>` in a terminal.
///
/// The probe deliberately passes no tool argument: mise errors out when asked
/// about a tool the current config does not manage, and the parser needs valid
/// JSON on stdout regardless (the service ignores exit codes).
PackageManagerSpec miseSpec({String tool = miseToolName}) => PackageManagerSpec(
  displayName: 'mise',
  packageId: tool,
  executable: 'mise',
  probeArgs: ['outdated', '--json'],
  upgradeCommand: ['mise', 'upgrade', tool],
  parseAvailableVersion: (stdout) => parseMiseOutdated(stdout, tool: tool),
);

/// Reads the available version from `mise outdated --json` output.
///
/// The payload maps tool name to `{"current": .., "latest": .., …}` and lists
/// only tools that are behind, so `{}` means up to date. Returns the `latest`
/// field of [tool], or `null` when the tool is absent (including installs made
/// under the raw backend id `github:dmezhnov/knitcalc`, which `mise upgrade
/// knitcalc` could not update anyway) or on malformed JSON.
String? parseMiseOutdated(String stdout, {required String tool}) {
  final Object? decoded;

  try {
    decoded = jsonDecode(stdout);
  } on FormatException {
    return null;
  }

  if (decoded is! Map) {
    return null;
  }

  final entry = decoded[tool];

  if (entry is! Map) {
    return null;
  }

  final latest = entry['latest'];

  return latest is String && latest.isNotEmpty ? latest : null;
}
