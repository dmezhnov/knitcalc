import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';
import 'package:knitcalc/update/update_service.dart';

// Real implementation on dart:io targets (desktop); inert on web, where no
// package manager exists, so the factory keeps compiling there.
import 'package_manager_service_stub.dart'
    if (dart.library.io) 'package_manager_service_io.dart'
    as impl;

/// Returns a package-manager-backed updater for [spec]: it probes the manager
/// for an available upgrade and, on update, runs the manager's upgrade command
/// in a visible terminal before quitting.
UpdateService createPackageManagerUpdateService(PackageManagerSpec spec) =>
    impl.createPackageManagerUpdateService(spec);
