import 'dart:io';

import 'package:archive/archive.dart';

/// Extracts the downloaded Windows bundle zip at [archivePath] over [installDir].
///
/// Run by the updater helper only after the app process has exited — both
/// native Windows and Wine/Proton keep the running executable, its DLLs and data
/// files (e.g. `icudtl.dat`) locked while the process is alive, so the swap
/// cannot happen in-process.
///
/// Each entry is written to a temp sibling and then atomically renamed over its
/// target, so the swap is per-file atomic. It overwrites and adds files but does
/// not delete entries dropped in the new version. May be retried by the caller
/// while file handles are still being released right after the parent exits.
void applyZipOverDirectory(String archivePath, String installDir) {
  final bytes = File(archivePath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  for (final entry in archive) {
    if (!entry.isFile) {
      continue;
    }

    final dest = File('$installDir/${entry.name}');
    dest.parent.createSync(recursive: true);

    final staged = File('${dest.path}.knitcalc-new');
    staged.writeAsBytesSync(entry.readBytes() ?? const <int>[]);
    staged.renameSync(dest.path);
  }
}
