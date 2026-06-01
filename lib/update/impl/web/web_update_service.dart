import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/update_service.dart';

// Resolves to the real web implementation on the web target and to an inert
// stub elsewhere. The web channel only ever occurs on web, so the stub is just
// there to keep non-web builds compiling.
import 'web_update_service_stub.dart'
    if (dart.library.js_interop) 'web_update_service_web.dart'
    as impl;

/// Builds the [UpdateService] for the web channel.
UpdateService createWebUpdateService(AppVersion? current) =>
    impl.createWebUpdateService(current);
