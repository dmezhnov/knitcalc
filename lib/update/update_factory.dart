import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/current_version.dart';
import 'package:knitcalc/update/impl/android/android_update_service.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/web/web_update_service.dart';
import 'package:knitcalc/update/update_service.dart';

/// Returns the [UpdateService] implementation for the given [channel].
///
/// During Phase 1 every channel maps to [NoopUpdateService]; later phases swap
/// in real implementations (Play in-app, Sparkle/WinSparkle, GitHub Releases,
/// service worker) channel by channel without touching call sites.
UpdateService createUpdateService(Channel channel) {
  switch (channel) {
    // Web: compare the deployed version.json with the running build, reload.
    case Channel.web:
      return createWebUpdateService(currentAppVersion());

    // Sideload: check GitHub Releases, download the APK and launch the
    // system installer.
    case Channel.androidSideload:
      return createAndroidUpdateService(currentAppVersion());

    // No store presence yet, so Play/RuStore installs update through the
    // store itself; nothing for the app to do until those listings exist.
    // TODO(update): Phase 3 follow-up — in_app_update for Play.
    case Channel.androidPlay:
    // TODO(update): Phase 3 follow-up — RuStore SDK.
    case Channel.androidRustore:
    // TODO(update): Phase 5 — upgrader (iTunes Lookup + deep link).
    case Channel.iosAppStore:
    // TODO(update): Phase 4 — Sparkle/WinSparkle via auto_updater.
    case Channel.macosManual:
    case Channel.windowsManual:
    // TODO(update): Phase 5 — format-aware GitHub update.
    case Channel.linuxAppImage:
    case Channel.linuxDpkg:
    case Channel.linuxTarball:
    // Externally managed or unknown: nothing for the app to do.
    case Channel.macosAppStore:
    case Channel.windowsStore:
    case Channel.linuxManaged:
    case Channel.unknown:
      return const NoopUpdateService();
  }
}
