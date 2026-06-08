import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/pm/package_manager_update_service.dart';
import 'package:knitcalc/update/update_service.dart';

/// Non-dart:io fallback (e.g. web): no package manager exists there.
UpdateService createPackageManagerUpdateService(PackageManagerSpec spec) =>
    const NoopUpdateService();
