import 'dart:io';

import 'package:archive/archive.dart';

/// Applies the downloaded Windows bundle zip at [archivePath] over [installDir]
/// in-process — the Wine/Proton update path.
///
/// On Linux (which is what Wine/Proton run on) the running executable and its
/// DLLs are plain data files with no Windows-style sharing lock, so the bundle
/// can be replaced while the app is still running. Native Windows cannot do this
/// — there a detached PowerShell script must wait for the process to exit first
/// (see buildWindowsUpdateScript).
///
/// Each entry is written to a temp sibling and then atomically renamed over its
/// target, so a file currently mmap'd by the running process is swapped by inode
/// rather than truncated in place (an in-place truncate could corrupt the live
/// process before it relaunches). Like the Windows path, this overwrites and
/// adds files but does not delete entries dropped in the new version.
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
