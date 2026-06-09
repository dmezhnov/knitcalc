import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// macOS, installed via Homebrew Cask — updated with `brew upgrade --cask`.
  macosHomebrew,

  /// macOS, installed manually (.zip) — download a new .app from GitHub.
  macosManual,

  /// Windows from the Microsoft Store (MSIX) — updated by the store itself.
  windowsStore,

  /// Windows, installed via winget — updated with `winget upgrade`.
  windowsWinget,

  /// Windows, installed via Scoop — updated with `scoop update`.
  windowsScoop,

  /// Windows, installed via Chocolatey — updated with `choco upgrade`.
  windowsChocolatey,

  /// Windows, installed manually (.zip) — download a new zip from GitHub.
  windowsManual,

  /// Linux under snap — updated with `snap refresh`.
  linuxSnap,

  /// Linux under flatpak — updated with `flatpak update`.
  linuxFlatpak,

  /// Linux under an unidentified external manager — left to the daemon.
  linuxManaged,

  /// Linux AppImage — replace the file via GitHub.
  linuxAppImage,

  /// Linux from a .deb — updated with `apt-get install --only-upgrade`.
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
    return _detectAndroidChannel();
  }

  if (Platform.isIOS) {
    return Channel.iosAppStore;
  }

  if (Platform.isMacOS) {
    // TODO(update): check for the presence of _MASReceipt for macosAppStore.
    return macosChannelForExecutable(Platform.resolvedExecutable);
  }

  if (Platform.isWindows) {
    // TODO(update): GetCurrentPackageFullName() -> windowsStore when MSIX.
    return windowsChannelForExecutable(Platform.resolvedExecutable);
  }

  if (Platform.isLinux) {
    return _detectLinuxChannel();
  }

  return Channel.unknown;
}

/// Method channel shared with the Android host (see `MainActivity`).
const MethodChannel _androidUpdateChannel = MethodChannel(
  'knitcalc/android_update',
);

/// Resolves the Android channel by asking the host for the installer package.
Future<Channel> _detectAndroidChannel() async {
  String? installer;

  try {
    installer = await _androidUpdateChannel.invokeMethod<String>(
      'getInstallerPackageName',
    );
  } on PlatformException {
    installer = null;
  } on MissingPluginException {
    installer = null;
  }

  return androidChannelForInstaller(installer);
}

/// Maps an Android installer package name to its [Channel].
///
/// `com.android.vending` is Google Play and `ru.vk.store` is RuStore; anything
/// else (manual install, `adb`, a file manager) is treated as a sideload that
/// updates through GitHub Releases.
Channel androidChannelForInstaller(String? installer) {
  switch (installer) {
    case 'com.android.vending':
      return Channel.androidPlay;
    case 'ru.vk.store':
      return Channel.androidRustore;
    default:
      return Channel.androidSideload;
  }
}

/// Maps a Windows executable path to its [Channel].
///
/// Each Windows package manager unpacks the app under its own directory, so
/// the executable path identifies the owner — and the owner must run the
/// update rather than the app swapping its own files behind the manager's
/// back:
///
/// - winget portable/zip packages live under `…\WinGet\Packages\<id>\…`;
/// - Scoop apps live under `…\scoop\apps\<name>\…` (the `scoop` segment is the
///   default root for both per-user and global installs; a custom-named
///   `$env:SCOOP` root is not recognized and falls back to manual);
/// - Chocolatey unpacks zip packages under `…\chocolatey\lib\<id>\…`.
///
/// Anything else is treated as a manually unzipped bundle (GitHub self-update).
Channel windowsChannelForExecutable(String executablePath) {
  final normalized = executablePath.toLowerCase().replaceAll('/', '\\');

  if (normalized.contains('\\winget\\packages\\')) {
    return Channel.windowsWinget;
  }

  if (normalized.contains('\\scoop\\apps\\')) {
    return Channel.windowsScoop;
  }

  if (normalized.contains('\\chocolatey\\lib\\')) {
    return Channel.windowsChocolatey;
  }

  return Channel.windowsManual;
}

/// Maps a macOS executable path to its [Channel].
///
/// Homebrew Cask installs an app under `…/Caskroom/<name>/…` (the copy in
/// `/Applications` is a clone or symlink of it), so an executable resolving into
/// a Caskroom is owned by Homebrew and updates with `brew upgrade --cask`.
/// Anything else is a manually unzipped `.app` (GitHub self-update).
Channel macosChannelForExecutable(String executablePath) {
  if (executablePath.contains('/Caskroom/')) {
    return Channel.macosHomebrew;
  }

  return Channel.macosManual;
}

/// Detects the Linux install format entirely in Dart, without platform code.
Channel _detectLinuxChannel() {
  final env = Platform.environment;

  if (env.containsKey('SNAP')) {
    return Channel.linuxSnap;
  }

  if (File('/.flatpak-info').existsSync()) {
    return Channel.linuxFlatpak;
  }

  if (env.containsKey('APPIMAGE')) {
    return Channel.linuxAppImage;
  }

  // A bundle living under the system prefix came from a .deb (dpkg/apt); a
  // bundle anywhere else (home dir, /opt) is an unpacked tarball.
  if (linuxIsSystemInstall(Platform.resolvedExecutable)) {
    return Channel.linuxDpkg;
  }

  return Channel.linuxTarball;
}

/// Whether a Linux executable path sits under the system package prefix and is
/// therefore owned by the distro package manager (apt/dpkg) rather than an
/// unpacked tarball the user dropped in their home directory or `/opt`.
bool linuxIsSystemInstall(String executablePath) =>
    executablePath.startsWith('/usr/');
