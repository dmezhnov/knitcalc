import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/update_service.dart';

/// Non-web fallback. The web channel never runs off the web target, so this
/// only exists to satisfy the conditional import on native builds.
UpdateService createWebUpdateService(AppVersion? current) =>
    const NoopUpdateService();
