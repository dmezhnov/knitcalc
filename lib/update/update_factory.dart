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
import 'package:knitcalc/update/impl/pm/specs/mise_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/scoop_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/snap_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/winget_spec.dart';
import 'package:knitcalc/update/impl/store/ios_app_store_service.dart';
import 'package:knitcalc/update/impl/store/play_update_service.dart';
import 'package:knitcalc/update/impl/store/store_listing_service.dart';
import 'package:knitcalc/update/impl/web/web_update_service.dart';
import 'package:knitcalc/update/impl/windows/windows_portable_update_service.dart';
import 'package:knitcalc/update/impl/windows/windows_update_service.dart';
import 'package:knitcalc/update/update_service.dart';

/// Whether this build may download a release APK and hand it to the system
/// installer.
///
/// False only in the no-sideload build (`mise build apk-nosideload`), which
/// ships without `REQUEST_INSTALL_PACKAGES` for the catalogues that refuse that
/// permission (RuStore rejected a release over it) — see
/// android/app/src/nosideload/AndroidManifest.xml. Without the permission the
/// install intent is refused by the system, so a build that dropped it must not
/// offer the sideload update at all; the store that distributes such a build
/// updates the app itself.
const bool sideloadInstallSupported = bool.fromEnvironment(
  'KNITCALC_SIDELOAD_INSTALL',
  defaultValue: true,
);

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
    // system installer — unless this build has no permission to install
    // packages (the no-sideload APK), in which case it stays silent.
    case Channel.androidSideload:
      return sideloadInstallSupported
          ? createAndroidUpdateService(currentAppVersion())
          : const NoopUpdateService();

    // Google Play: Play itself reports update availability and ships the
    // binary; run the flexible in-app update flow (no GitHub, no review lag).
    case Channel.androidPlay:
      return createPlayUpdateService();

    // App Store: ask iTunes Lookup for the live store version, then open the
    // listing to update there.
    case Channel.iosAppStore:
      return createIosAppStoreService(currentAppVersion());

    // Samsung Galaxy Store, Amazon Appstore, Huawei AppGallery, F-Droid,
    // Accrescent, RuStore: the store ships and installs the binary, so the app
    // does not
    // self-update; it shows the banner from the version the store published in
    // the remote store-versions document and opens the listing on update.
    // (RuStore also has flutter_rustore_update for an in-app flow; it stays
    // rejected — an extra dependency for what this service already does.)
    case Channel.androidSamsung:
    case Channel.androidAmazon:
    case Channel.androidHuawei:
    case Channel.androidFdroid:
    case Channel.androidAccrescent:
    case Channel.androidRustore:
      return createStoreListingService(channel, currentAppVersion());

    // Package-manager installs: the manager owns updates — probe it for
    // availability (no GitHub, no lag) and run its upgrade command in a
    // terminal. Package ids inside the specs are placeholders until published.
    case Channel.windowsScoop:
      return createPackageManagerUpdateService(scoopSpec());
    case Channel.windowsChocolatey:
      return createPackageManagerUpdateService(chocolateySpec());
    case Channel.windowsWinget:
      return createPackageManagerUpdateService(wingetSpec());
    case Channel.macosHomebrew:
      return createPackageManagerUpdateService(homebrewSpec());
    case Channel.linuxSnap:
      return createPackageManagerUpdateService(snapSpec());
    case Channel.linuxFlatpak:
      return createPackageManagerUpdateService(flatpakSpec());
    case Channel.linuxDpkg:
      return createPackageManagerUpdateService(aptSpec());
    // mise, on any desktop OS: it unpacks the release asset into its own
    // install directory, so the upgrade goes through `mise upgrade`.
    case Channel.mise:
      return createPackageManagerUpdateService(miseSpec());

    // Manually installed macOS app bundle: download the new zip from GitHub
    // Releases and swap the .app in via a detached script after the app exits.
    case Channel.macosManual:
      return createMacosUpdateService(currentAppVersion());

    // Directly-installed Windows app (Inno installer, not via a package
    // manager): download the new installer from GitHub Releases and run it
    // silently — it swaps the bundle in place and relaunches after the app
    // exits. winget installs use windowsWinget above instead.
    case Channel.windowsManual:
      return createWindowsUpdateService(currentAppVersion());

    // Portable Windows copy (loose zip, no installer marker): download the new
    // zip from GitHub Releases and swap the portable folder's files in place via
    // a detached script after the app exits — no installer, no second copy.
    case Channel.windowsPortable:
      return createWindowsPortableUpdateService(currentAppVersion());

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
