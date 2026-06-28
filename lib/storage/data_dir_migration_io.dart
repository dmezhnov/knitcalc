import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The marker file used to decide whether [migrateDataDir] has anything to do:
/// if the new directory already holds the saved-projects store, it is either a
/// fresh install or a completed migration, so we must not overwrite it.
const String _markerFile = 'shared_preferences.json';

/// Carries an existing install's data over after the Windows CompanyName changed
/// from the Flutter template `com.example` to `dmezhnov`, which moved the
/// app-support directory from `%APPDATA%\com.example\knitcalc` to
/// `%APPDATA%\dmezhnov\knitcalc`. No-op on every other platform (their data
/// directory is keyed off the bundle id, which did not change).
Future<void> migrateLegacyDataDir() async {
  if (!Platform.isWindows) return;

  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) return;

  final from = Directory('$appData\\com.example\\knitcalc');
  final to = await getApplicationSupportDirectory();

  await migrateDataDir(from: from, to: to);
}

/// Copies every file from [from] into [to] and then removes [from]. Skips the
/// work when [from] is absent or when [to] already contains the saved-projects
/// store (so newer data is never clobbered). Pure filesystem logic, decoupled
/// from path_provider/Platform so it can be unit-tested with temp dirs.
Future<void> migrateDataDir({
  required Directory from,
  required Directory to,
}) async {
  if (!from.existsSync()) return;

  if (File('${to.path}${Platform.pathSeparator}$_markerFile').existsSync()) {
    return;
  }

  if (!to.existsSync()) {
    await to.create(recursive: true);
  }

  for (final entity in from.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    await entity.copy('${to.path}${Platform.pathSeparator}$name');
  }

  await from.delete(recursive: true);
}
