import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/update_service.dart';

/// Returns the [UpdateService] implementation for the given [channel].
///
/// During Phase 1 every channel maps to [NoopUpdateService]; later phases swap
/// in real implementations (Play in-app, Sparkle/WinSparkle, GitHub Releases,
/// service worker) channel by channel without touching call sites.
UpdateService createUpdateService(Channel channel) {
  switch (channel) {
    // TODO(update): Phase 3 — in_app_update.
    case Channel.androidPlay:
    // TODO(update): Phase 3 — RuStore SDK.
    case Channel.androidRustore:
    // TODO(update): Phase 3 — GitHub APK + REQUEST_INSTALL_PACKAGES.
    case Channel.androidSideload:
    // TODO(update): Phase 5 — upgrader (iTunes Lookup + deep link).
    case Channel.iosAppStore:
    // TODO(update): Phase 4 — Sparkle/WinSparkle via auto_updater.
    case Channel.macosManual:
    case Channel.windowsManual:
    // TODO(update): Phase 5 — format-aware GitHub update.
    case Channel.linuxAppImage:
    case Channel.linuxDpkg:
    case Channel.linuxTarball:
    // TODO(update): Phase 2 — service worker reload dialog.
    case Channel.web:
    // Externally managed or unknown: nothing for the app to do.
    case Channel.macosAppStore:
    case Channel.windowsStore:
    case Channel.linuxManaged:
    case Channel.unknown:
      return const NoopUpdateService();
  }
}
