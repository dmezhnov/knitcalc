import 'dart:io';

import 'package:flutter/foundation.dart';

/// Distribution channel that determines the update mechanism.
///
/// The channel is detected at runtime where reliable (web, Linux format) and,
/// where platform code is needed (Android install source, macOS MAS check,
/// Windows MSIX check), a default is returned for now with a TODO for the
/// method channel. The build-time fallback is
/// `--dart-define=UPDATE_CHANNEL=<name>`.
enum Channel {
  /// Android, installed from Google Play.
  androidPlay,

  /// Android, installed from RuStore.
  androidRustore,

  /// Android, installed manually (sideload) — updated via GitHub.
  androidSideload,

  /// iOS — always the App Store.
  iosAppStore,

  /// macOS from the Mac App Store.
  macosAppStore,

  /// macOS, installed manually (.dmg/.zip) — Sparkle + appcast.
  macosManual,

  /// Windows from the Microsoft Store (MSIX) — updated by the store itself.
  windowsStore,

  /// Windows, installed manually (.msi/.exe) — WinSparkle + appcast.
  windowsManual,

  /// Linux under snap or flatpak — updated by the daemon.
  linuxManaged,

  /// Linux AppImage — replace the file via GitHub.
  linuxAppImage,

  /// Linux from a .deb — updated via the package manager.
  linuxDpkg,

  /// Linux from a tarball — download a new tar.gz from GitHub.
  linuxTarball,

  /// Web — service worker, reload on a new version.
  web,

  /// The channel could not be determined.
  unknown;

  static Channel? _fromName(String name) {
    for (final channel in Channel.values) {
      if (channel.name == name) {
        return channel;
      }
    }

    return null;
  }
}

/// Build-time fallback: `flutter build ... --dart-define=UPDATE_CHANNEL=play`.
const String _channelOverride = String.fromEnvironment('UPDATE_CHANNEL');

/// Detects the distribution channel of the current build.
///
/// The `UPDATE_CHANNEL` build-time override is considered first, then platform
/// detection. Some branches are stubs until platform code is wired up
/// (see Phases 3–5) and are marked with TODO.
Future<Channel> detectChannel() async {
  if (_channelOverride.isNotEmpty) {
    final overridden = Channel._fromName(_channelOverride);

    if (overridden != null) {
      return overridden;
    }
  }

  if (kIsWeb) {
    return Channel.web;
  }

  if (Platform.isAndroid) {
    // TODO(update): method channel to PackageManager.getInstallSourceInfo()
    // (com.android.vending -> play, ru.vk.store -> rustore, else sideload).
    return Channel.androidSideload;
  }

  if (Platform.isIOS) {
    return Channel.iosAppStore;
  }

  if (Platform.isMacOS) {
    // TODO(update): check for the presence of _MASReceipt for macosAppStore.
    return Channel.macosManual;
  }

  if (Platform.isWindows) {
    // TODO(update): GetCurrentPackageFullName() -> windowsStore when MSIX.
    return Channel.windowsManual;
  }

  if (Platform.isLinux) {
    return _detectLinuxChannel();
  }

  return Channel.unknown;
}

/// Detects the Linux install format entirely in Dart, without platform code.
Channel _detectLinuxChannel() {
  final env = Platform.environment;

  if (env.containsKey('SNAP') || File('/.flatpak-info').existsSync()) {
    return Channel.linuxManaged;
  }

  if (env.containsKey('APPIMAGE')) {
    return Channel.linuxAppImage;
  }

  // TODO(update): distinguish a dpkg install from a tarball (dpkg-query by path).
  return Channel.linuxTarball;
}
