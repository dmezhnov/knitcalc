import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_service.dart';

// Real implementation on dart:io targets (Windows); inert elsewhere so the
// factory keeps compiling on web.
import 'windows_update_service_stub.dart'
    if (dart.library.io) 'windows_update_service_io.dart'
    as impl;

/// Returns the Windows manual-install updater: checks GitHub `releases/latest`,
/// downloads the bundle zip and swaps it in via a detached PowerShell script.
UpdateService createWindowsUpdateService(AppVersion? current) =>
    impl.createWindowsUpdateService(current);
