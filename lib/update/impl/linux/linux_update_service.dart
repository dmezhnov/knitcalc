import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_service.dart';

// Real implementation on dart:io targets (Linux); inert elsewhere so the
// factory keeps compiling on web.
import 'linux_update_service_stub.dart'
    if (dart.library.io) 'linux_update_service_io.dart'
    as impl;

/// Returns the Linux manual-install updater: checks GitHub `releases/latest`,
/// downloads the bundle tarball and swaps it in via a detached script.
UpdateService createLinuxUpdateService(AppVersion? current) =>
    impl.createLinuxUpdateService(current);
