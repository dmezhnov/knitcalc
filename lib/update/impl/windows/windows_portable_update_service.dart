import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_service.dart';

// Real implementation on dart:io targets (Windows); inert elsewhere so the
// factory keeps compiling on web.
import 'windows_portable_update_service_stub.dart'
    if (dart.library.io) 'windows_portable_update_service_io.dart'
    as impl;

/// Returns the Windows portable-copy updater: reads the available version from
/// the remote store-versions document, downloads the new zip and swaps the
/// portable folder's files in place via a detached script.
UpdateService createWindowsPortableUpdateService(AppVersion? current) =>
    impl.createWindowsPortableUpdateService(current);
