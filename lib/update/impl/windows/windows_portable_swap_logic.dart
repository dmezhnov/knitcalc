/// Builds the detached PowerShell script that applies a downloaded portable
/// Windows build.
///
/// The app must quit after spawning it: the script waits for [pid] to exit (so
/// the running exe and its DLLs are no longer locked — Windows holds file locks
/// for the lifetime of the process), extracts [archivePath] — the
/// `knitcalc-windows-x64-*.zip`, whose files sit at the archive root — into a
/// fresh [stagingDir], copies them over [installDir] in place, removes the
/// archive and staging dir, then relaunches [executablePath]. The new build
/// then sees its own version on next launch.
///
/// Every path is baked in (PowerShell single-quoted, with embedded quotes
/// doubled) so paths with spaces stay intact; [pid] is numeric. Targets native
/// Windows PowerShell; running a portable build under Wine is out of scope.
String buildWindowsPortableUpdateScript({
  required int pid,
  required String archivePath,
  required String stagingDir,
  required String installDir,
  required String executablePath,
}) {
  final archive = _psQuote(archivePath);
  final staging = _psQuote(stagingDir);
  final install = _psQuote(installDir);
  final exe = _psQuote(executablePath);

  return [
    '# KnitCalc self-update: wait for the running app to exit, swap the portable',
    '# folder files with the freshly downloaded build, then relaunch.',
    "\$ErrorActionPreference = 'Stop'",
    'while (Get-Process -Id $pid -ErrorAction SilentlyContinue) {',
    '  Start-Sleep -Milliseconds 200',
    '}',
    'Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue',
    'New-Item -ItemType Directory -Force -Path $staging | Out-Null',
    'Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force',
    "Copy-Item -Path (Join-Path $staging '*') -Destination $install -Recurse -Force",
    'Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue',
    'Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue',
    'Start-Process -FilePath $exe -WorkingDirectory $install',
    '',
  ].join('\n');
}

/// Wraps [path] in a PowerShell single-quoted literal, doubling any embedded
/// single quote so the value is taken verbatim (no variable/escape expansion).
String _psQuote(String path) => "'${path.replaceAll("'", "''")}'";
