import 'dart:convert';

import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';

// TODO(update): replace with the real Homebrew cask token once published.
const String homebrewCask = 'knitcalc';

/// Homebrew Cask updater spec. `brew outdated --json` reports outdated casks;
/// the upgrade runs `brew upgrade --cask` in a terminal.
PackageManagerSpec homebrewSpec({String cask = homebrewCask}) =>
    PackageManagerSpec(
      displayName: 'Homebrew',
      packageId: cask,
      executable: 'brew',
      probeArgs: ['outdated', '--cask', '--greedy', '--json', cask],
      upgradeCommand: ['brew', 'upgrade', '--cask', cask],
      parseAvailableVersion: parseBrewOutdated,
    );

/// Reads the available version from `brew outdated --cask --json` output.
///
/// The payload is `{"formulae": [...], "casks": [{"name": ..,
/// "current_version": ".."}]}`; an empty `casks` list means up to date. Returns
/// the first cask's `current_version`, or `null` when none / on malformed JSON.
String? parseBrewOutdated(String stdout) {
  final Object? decoded;

  try {
    decoded = jsonDecode(stdout);
  } on FormatException {
    return null;
  }

  if (decoded is! Map) {
    return null;
  }

  final casks = decoded['casks'];

  if (casks is! List || casks.isEmpty) {
    return null;
  }

  final first = casks.first;

  if (first is! Map) {
    return null;
  }

  final version = first['current_version'];

  return version is String && version.isNotEmpty ? version : null;
}
