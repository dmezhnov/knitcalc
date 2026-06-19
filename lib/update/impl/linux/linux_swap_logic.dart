/// Builds the detached `/bin/sh` script that applies a downloaded Linux bundle.
///
/// The app must quit after spawning it: the script waits for [pid] to disappear
/// (so the running executable is no longer busy), unpacks [archivePath] over
/// [installDir] (the bundle directory), removes the archive and relaunches
/// [executablePath]. The new build then sees its own version on next launch.
String buildLinuxUpdateScript({
  required int pid,
  required String archivePath,
  required String installDir,
  required String executablePath,
}) =>
    '#!/bin/sh\n'
    '# KnitCalc self-update: wait for the running app to exit, unpack the new\n'
    '# bundle over the install directory, then relaunch.\n'
    'set -e\n'
    'while kill -0 $pid 2>/dev/null; do\n'
    '  sleep 0.2\n'
    'done\n'
    'tar -xzf "$archivePath" -C "$installDir"\n'
    'rm -f "$archivePath"\n'
    'exec "$executablePath"\n';
