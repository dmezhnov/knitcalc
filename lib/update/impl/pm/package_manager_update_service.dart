import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/update_service.dart';

/// Minimal result of a probe command, decoupled from `dart:io`'s `ProcessResult`
/// so this file (and its tests) stay platform-independent and web-compilable.
class ProcessOutput {
  const ProcessOutput({required this.exitCode, required this.stdout});

  final int exitCode;
  final String stdout;
}

/// Runs a command and returns its captured output. The default implementation
/// (see `package_manager_service_io.dart`) wraps `Process.run`; tests inject a
/// fake so the service logic runs without spawning a real package manager.
typedef ProcessRunner =
    Future<ProcessOutput> Function(String executable, List<String> arguments);

/// Opens a visible terminal running [command] and then quits the app so the
/// package manager can replace the running files. The default implementation
/// (see `terminal_launcher.dart`) is per-OS; tests inject a fake.
typedef TerminalLauncher = Future<void> Function(List<String> command);

/// Describes how to talk to one package manager: how to ask whether an upgrade
/// is available (and read the version out of its output) and how to run the
/// upgrade. Command definitions and the parser are pure data/functions, so each
/// manager's spec is unit-testable without the manager installed.
class PackageManagerSpec {
  const PackageManagerSpec({
    required this.displayName,
    required this.packageId,
    required this.executable,
    required this.probeArgs,
    required this.upgradeCommand,
    required this.parseAvailableVersion,
  });

  /// Human name for logs/diagnostics (e.g. "winget", "Homebrew").
  final String displayName;

  /// Identifier of this app in the manager's catalog (winget id, brew cask,
  /// flatpak app id, snap/apt package name).
  final String packageId;

  /// The manager's binary (`winget`, `brew`, `flatpak`, `snap`, `apt-get`).
  final String executable;

  /// Arguments for the "is an upgrade available?" probe (read-only).
  final List<String> probeArgs;

  /// Full command line (argv, including the binary, and `sudo` where the
  /// manager needs root) run in the visible terminal to perform the upgrade.
  final List<String> upgradeCommand;

  /// Reads the available version out of the probe's stdout, or `null` when the
  /// app is up to date / not upgradable through this manager.
  final String? Function(String stdout) parseAvailableVersion;
}

/// [UpdateService] backed by a system package manager.
///
/// The manager itself is the source of truth for availability (no GitHub, so
/// the banner never gets ahead of what the manager can actually install), and
/// the upgrade runs through the manager's own command in a visible terminal.
class PackageManagerUpdateService implements UpdateService {
  const PackageManagerUpdateService({
    required this.spec,
    required ProcessRunner runner,
    required TerminalLauncher launcher,
  }) : _runner = runner,
       _launcher = launcher;

  final PackageManagerSpec spec;
  final ProcessRunner _runner;
  final TerminalLauncher _launcher;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final ProcessOutput output;

    try {
      output = await _runner(spec.executable, spec.probeArgs);
    } on Object {
      // Manager missing or probe failed to spawn: skip, retry next launch.
      return null;
    }

    // Exit code is intentionally not gated on: managers differ (some return
    // non-zero when there is no upgrade), so the parser reads stdout and is the
    // sole arbiter of whether an upgrade is on offer.
    final version = spec.parseAvailableVersion(output.stdout);

    if (version == null) {
      return null;
    }

    return UpdateInfo(
      latestVersion: AppVersion.tryParse(version) ?? const AppVersion(0, 0, 0),
      versionLabel: version,
      action: UpdateAction.runCommand,
    );
  }

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    DownloadControl? control,
  }) async {
    // Hands off to a visible terminal and (on the default launcher) quits the
    // app so the manager can swap the running files; control does not return.
    await _launcher(spec.upgradeCommand);
  }
}
