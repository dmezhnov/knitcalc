import 'dart:io';

import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';
import 'package:knitcalc/update/impl/pm/terminal_launcher.dart';
import 'package:knitcalc/update/update_service.dart';

/// Wires the package-manager service with the real `Process.run` probe and the
/// per-OS visible-terminal launcher.
UpdateService createPackageManagerUpdateService(PackageManagerSpec spec) =>
    PackageManagerUpdateService(
      spec: spec,
      runner: _runProcess,
      launcher: launchInTerminal,
    );

/// Default [ProcessRunner]: spawns the manager and captures stdout. The probe
/// commands are read-only (`upgrade --id`, `outdated`, `remote-ls`, …), so this
/// never mutates anything; the mutating upgrade goes through the terminal.
Future<ProcessOutput> _runProcess(
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(executable, arguments);

  return ProcessOutput(
    exitCode: result.exitCode,
    stdout: result.stdout is String ? result.stdout as String : '',
  );
}
