import 'dart:io';

/// Opens a visible terminal running [command], then quits this app so the
/// package manager can replace the running files (and so any UAC/sudo prompt is
/// answered by the user). Throws if no terminal could be opened — the caller
/// then surfaces a failure instead of exiting.
///
/// The terminal stays open after the command finishes so the user can read the
/// result (and answer prompts). This is the default [TerminalLauncher]; tests
/// inject a fake instead.
Future<void> launchInTerminal(List<String> command) async {
  if (Platform.isWindows) {
    await _launchWindows(command);
  } else if (Platform.isMacOS) {
    await _launchMacos(command);
  } else if (Platform.isLinux) {
    await _launchLinux(command);
  } else {
    throw UnsupportedError('No terminal launcher for this platform');
  }

  exit(0);
}

/// `start "" cmd /k <command>` opens a new console window and `/k` keeps it open
/// after the upgrade finishes. winget elevates itself (UAC) when needed.
Future<void> _launchWindows(List<String> command) async {
  await Process.start('cmd', [
    '/c',
    'start',
    '',
    'cmd',
    '/k',
    ...command,
  ], mode: ProcessStartMode.detached);
}

/// AppleScript opens Terminal.app and runs the command in a new window/tab.
Future<void> _launchMacos(List<String> command) async {
  final script =
      'tell application "Terminal" to do script "${_shellJoin(command)}"';

  await Process.start('osascript', [
    '-e',
    script,
  ], mode: ProcessStartMode.detached);
}

/// Linux has no standard terminal, so try the common emulators in turn. The
/// command runs inside `sh -c` with a trailing pause so the window stays open
/// and any `sudo` prompt (snap/apt) can be answered.
Future<void> _launchLinux(List<String> command) async {
  final inner =
      '${_shellJoin(command)}; echo; printf "[Enter to close] "; read _';

  // (emulator, flag) pairs; the flag precedes the command to run.
  const emulators = [
    ['x-terminal-emulator', '-e'],
    ['gnome-terminal', '--'],
    ['konsole', '-e'],
    ['xterm', '-e'],
  ];

  for (final emulator in emulators) {
    try {
      await Process.start(emulator[0], [
        emulator[1],
        'sh',
        '-c',
        inner,
      ], mode: ProcessStartMode.detached);

      return;
    } on ProcessException {
      // Emulator not installed: try the next one.
      continue;
    }
  }

  throw const ProcessException('terminal', [], 'No terminal emulator found');
}

/// Joins argv into a shell command line, single-quoting any token that contains
/// characters the shell would interpret. Package ids here are plain (letters,
/// digits, `.`, `-`, `/`), so quoting rarely triggers, but it keeps the join
/// safe if an id ever needs it.
String _shellJoin(List<String> command) => command.map(_quote).join(' ');

String _quote(String token) {
  final safe = RegExp(r'^[A-Za-z0-9._\-/:]+$');

  if (safe.hasMatch(token)) {
    return token;
  }

  // Wrap in single quotes, escaping embedded single quotes the POSIX way.
  return "'${token.replaceAll("'", r"'\''")}'";
}
