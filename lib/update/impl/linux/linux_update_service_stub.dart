import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/update_service.dart';

/// Non-dart:io fallback (e.g. web): the Linux updater never applies there.
UpdateService createLinuxUpdateService(AppVersion? current) =>
    const NoopUpdateService();
