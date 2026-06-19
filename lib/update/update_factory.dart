import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/current_version.dart';
import 'package:knitcalc/update/impl/android/android_update_service.dart';
import 'package:knitcalc/update/impl/linux/linux_update_service.dart';
import 'package:knitcalc/update/impl/macos/macos_update_service.dart';
import 'package:knitcalc/update/impl/noop_update_service.dart';
import 'package:knitcalc/update/impl/pm/package_manager_service.dart';
import 'package:knitcalc/update/impl/pm/specs/apt_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/chocolatey_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/flatpak_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/homebrew_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/scoop_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/snap_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/winget_spec.dart';
import 'package:knitcalc/update/impl/store/ios_app_store_service.dart';
import 'package:knitcalc/update/impl/store/play_update_service.dart';
import 'package:knitcalc/update/impl/store/store_listing_service.dart';
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

    // Google Play: Play itself reports update availability and ships the
    // binary; run the flexible in-app update flow (no GitHub, no review lag).
    case Channel.androidPlay:
      return createPlayUpdateService();

    // App Store: ask iTunes Lookup for the live store version, then open the
    // listing to update there.
    case Channel.iosAppStore:
      return createIosAppStoreService(currentAppVersion());

    // RuStore in-app update is pending a minSdk 24 bump and on-device build
    // verification; until then RuStore installs update through the store.
    // TODO(update): wire flutter_rustore_update once minSdk is raised to 24.
    case Channel.androidRustore:
      return const NoopUpdateService();

    // Samsung Galaxy Store, Amazon Appstore, Huawei AppGallery, F-Droid,
    // Accrescent: the store ships and installs the binary, so the app does not
    // self-update; it shows the banner from the version the store published in
    // the remote store-versions document and opens the listing on update.
    case Channel.androidSamsung:
    case Channel.androidAmazon:
    case Channel.androidHuawei:
    case Channel.androidFdroid:
    case Channel.androidAccrescent:
      return createStoreListingService(channel, currentAppVersion());

    // Package-manager installs: the manager owns updates — probe it for
    // availability (no GitHub, no lag) and run its upgrade command in a
    // terminal. Package ids inside the specs are placeholders until published.
    case Channel.windowsWinget:
      return createPackageManagerUpdateService(wingetSpec());
    case Channel.windowsScoop:
      return createPackageManagerUpdateService(scoopSpec());
    case Channel.windowsChocolatey:
      return createPackageManagerUpdateService(chocolateySpec());
    case Channel.macosHomebrew:
      return createPackageManagerUpdateService(homebrewSpec());
    case Channel.linuxSnap:
      return createPackageManagerUpdateService(snapSpec());
    case Channel.linuxFlatpak:
      return createPackageManagerUpdateService(flatpakSpec());
    case Channel.linuxDpkg:
      return createPackageManagerUpdateService(aptSpec());

    // Manually installed macOS app bundle: download the new zip from GitHub
    // Releases and swap the .app in via a detached script after the app exits.
    case Channel.macosManual:
      return createMacosUpdateService(currentAppVersion());

    // Manually installed Windows bundle: download the new zip from GitHub
    // Releases and swap it in via a detached updater helper after the app exits.
    case Channel.windowsManual:
      return createWindowsUpdateService(currentAppVersion());

    // Manually installed Linux bundle: download the new tarball from GitHub
    // Releases and swap it in via a detached script.
    case Channel.linuxTarball:
      return createLinuxUpdateService(currentAppVersion());

    // TODO(update): Phase 5 — AppImage self-replace. No such release asset
    // exists yet, so it stays no-op for now.
    case Channel.linuxAppImage:
    // Externally managed or unknown: nothing for the app to do.
    case Channel.macosAppStore:
    case Channel.windowsStore:
    case Channel.linuxManaged:
    case Channel.unknown:
      return const NoopUpdateService();
  }
}
