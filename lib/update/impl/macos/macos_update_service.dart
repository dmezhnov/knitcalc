import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_service.dart';

// Real implementation on dart:io targets (macOS); inert elsewhere so the
// factory keeps compiling on web.
import 'macos_update_service_stub.dart'
    if (dart.library.io) 'macos_update_service_io.dart'
    as impl;

/// Returns the macOS manual-install updater: checks GitHub `releases/latest`,
/// downloads the app-bundle zip and swaps it in via a detached script.
UpdateService createMacosUpdateService(AppVersion? current) =>
    impl.createMacosUpdateService(current);
