import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/current_version.dart';
import 'package:knitcalc/update/impl/android/android_update_service.dart';
import 'package:knitcalc/update/impl/linux/linux_update_service.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/web/web_update_service.dart';
import 'package:knitcalc/update/impl/windows/windows_update_service.dart';
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
    // TODO(update): Phase 4 — Sparkle via auto_updater.
    case Channel.macosManual:
      return const NoopUpdateService();

    // Manually installed Windows bundle: download the new zip from GitHub
    // Releases and swap it in via a detached PowerShell script.
    case Channel.windowsManual:
      return createWindowsUpdateService(currentAppVersion());

    // Manually installed Linux bundle: download the new tarball from GitHub
    // Releases and swap it in via a detached script.
    case Channel.linuxTarball:
      return createLinuxUpdateService(currentAppVersion());

    // TODO(update): Phase 5 — AppImage self-replace and dpkg via the package
    // manager. No such release assets exist yet, so they stay no-op for now.
    case Channel.linuxAppImage:
    case Channel.linuxDpkg:
    // Externally managed or unknown: nothing for the app to do.
    case Channel.macosAppStore:
    case Channel.windowsStore:
    case Channel.linuxManaged:
    case Channel.unknown:
      return const NoopUpdateService();
  }
}
