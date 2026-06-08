import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';
import 'package:knitcalc/update/update_info.dart';

PackageManagerSpec _spec(String? Function(String) parse) => PackageManagerSpec(
  displayName: 'test',
  packageId: 'knitcalc',
  executable: 'pm',
  probeArgs: const ['probe', 'knitcalc'],
  upgradeCommand: const ['sudo', 'pm', 'upgrade', 'knitcalc'],
  parseAvailableVersion: parse,
);

void main() {
  group('checkForUpdate', () {
    test('returns a runCommand update with the parsed version', () async {
      var probedExecutable = '';
      List<String> probedArgs = const [];

      final service = PackageManagerUpdateService(
        spec: _spec((_) => '1.9.0'),
        runner: (executable, args) async {
          probedExecutable = executable;
          probedArgs = args;
          return const ProcessOutput(exitCode: 0, stdout: 'whatever');
        },
        launcher: (_) async => fail('startUpdate not expected here'),
      );

      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.action, UpdateAction.runCommand);
      expect(info.versionLabel, '1.9.0');
      expect(info.latestVersion, const AppVersion(1, 9, 0));
      // Probed with the spec's executable + probe args.
      expect(probedExecutable, 'pm');
      expect(probedArgs, const ['probe', 'knitcalc']);
    });

    test('returns null when the parser reports no upgrade', () async {
      final service = PackageManagerUpdateService(
        spec: _spec((_) => null),
        runner: (_, _) async =>
            const ProcessOutput(exitCode: 0, stdout: 'up to date'),
        launcher: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('ignores the exit code and lets the parser decide', () async {
      // Some managers exit non-zero when there is no upgrade; a positive parse
      // on a non-zero exit must still surface the update.
      final service = PackageManagerUpdateService(
        spec: _spec((_) => '2.0.0'),
        runner: (_, _) async =>
            const ProcessOutput(exitCode: 1, stdout: 'has upgrade'),
        launcher: (_) async {},
      );

      expect((await service.checkForUpdate())?.versionLabel, '2.0.0');
    });

    test('returns null when the probe fails to spawn', () async {
      final service = PackageManagerUpdateService(
        spec: _spec((_) => '1.9.0'),
        runner: (_, _) async => throw const ProcessException('pm', []),
        launcher: (_) async {},
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test(
      'falls back to 0.0.0 when the version string is unparseable',
      () async {
        final service = PackageManagerUpdateService(
          spec: _spec((_) => 'stable'),
          runner: (_, _) async => const ProcessOutput(exitCode: 0, stdout: ''),
          launcher: (_) async {},
        );

        final info = await service.checkForUpdate();
        // The label is still shown; the comparable version degrades safely.
        expect(info!.versionLabel, 'stable');
        expect(info.latestVersion, const AppVersion(0, 0, 0));
      },
    );
  });

  group('startUpdate', () {
    test('launches the upgrade command and never re-probes', () async {
      List<String>? launched;
      var probed = false;

      final service = PackageManagerUpdateService(
        spec: _spec((_) => '1.9.0'),
        runner: (_, _) async {
          probed = true;
          return const ProcessOutput(exitCode: 0, stdout: '');
        },
        launcher: (command) async => launched = command,
      );

      await service.startUpdate(
        const UpdateInfo(
          latestVersion: AppVersion(1, 9, 0),
          action: UpdateAction.runCommand,
        ),
      );

      expect(launched, const ['sudo', 'pm', 'upgrade', 'knitcalc']);
      expect(probed, isFalse);
    });
  });
}
