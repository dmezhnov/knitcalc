import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_service.dart';

// Real implementation on dart:io targets (Android); inert elsewhere so the
// factory keeps compiling on web.
import 'android_update_service_stub.dart'
    if (dart.library.io) 'android_update_service_io.dart'
    as impl;

/// Returns the sideload update service: checks GitHub `releases/latest`,
/// downloads the APK and launches the system installer.
UpdateService createAndroidUpdateService(AppVersion? current) =>
    impl.createAndroidUpdateService(current);
