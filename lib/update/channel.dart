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

  /// Android, installed from the Samsung Galaxy Store.
  androidSamsung,

  /// Android, installed from the Amazon Appstore.
  androidAmazon,

  /// Android, installed from the Huawei AppGallery.
  androidHuawei,

  /// Android, installed from the F-Droid client.
  androidFdroid,

  /// Android, installed from the Accrescent client.
  androidAccrescent,

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

  /// Windows, installed via Scoop — updated with `scoop update`.
  windowsScoop,

  /// Windows, installed via Chocolatey — updated with `choco upgrade`.
  windowsChocolatey,

  /// Windows, installed via winget — updated with `winget upgrade`. The Inno
  /// installer stamps an `install_source` marker so a winget install (which runs
  /// the same installer) is told apart from a direct download.
  windowsWinget,

  /// Windows, installed by running the Inno Setup installer directly (not via a
  /// package manager) — self-updates by downloading and running the new
  /// installer from GitHub.
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

/// Installer package names of the stores/clients that report update
/// availability themselves but do NOT swap the binary behind our back. Each
/// resolves to its own per-store channel so the update banner can open that
/// store's listing (the store ships the actual binary; we only announce, using
/// the version published in the remote store-versions document):
///
/// - `com.sec.android.app.samsungapps` — Samsung Galaxy Store;
/// - `com.amazon.venezia` — Amazon Appstore;
/// - `com.huawei.appmarket` — Huawei AppGallery;
/// - `org.fdroid.fdroid` — the F-Droid client;
/// - `app.accrescent.client` — the Accrescent client.
///
/// Google Play (`com.android.vending`) and RuStore (`ru.vk.store`) keep
/// dedicated channels because their in-app update SDKs are wired (Play) or
/// pending (RuStore).
const Map<String, Channel> _storeInstallerChannels = {
  'com.sec.android.app.samsungapps': Channel.androidSamsung,
  'com.amazon.venezia': Channel.androidAmazon,
  'com.huawei.appmarket': Channel.androidHuawei,
  'org.fdroid.fdroid': Channel.androidFdroid,
  'app.accrescent.client': Channel.androidAccrescent,
};

/// Maps an Android installer package name to its [Channel].
///
/// `com.android.vending` is Google Play and `ru.vk.store` is RuStore; the other
/// known stores (see [_storeInstallerChannels]) map to a per-store channel;
/// anything else (manual install, `adb`, a file manager) is treated as a
/// sideload that updates through GitHub Releases.
Channel androidChannelForInstaller(String? installer) {
  switch (installer) {
    case 'com.android.vending':
      return Channel.androidPlay;
    case 'ru.vk.store':
      return Channel.androidRustore;
    default:
      return _storeInstallerChannels[installer] ?? Channel.androidSideload;
  }
}

/// Reads the Inno installer's `install_source` marker from the directory holding
/// the executable, trimmed, or `null` when it is absent. The installer writes
/// `winget` for a silent winget install and `manual` for a direct install (see
/// packaging/inno/knitcalc.iss); Scoop/Chocolatey installs have no marker.
typedef InstallSourceReader = String? Function(String executableDir);

String? _readInstallSourceMarker(String executableDir) {
  try {
    return File('$executableDir\\install_source').readAsStringSync().trim();
  } on FileSystemException {
    return null;
  }
}

String _executableDir(String executablePath) {
  final separator = executablePath.lastIndexOf(RegExp(r'[\\/]'));
  return separator >= 0 ? executablePath.substring(0, separator) : '.';
}

/// Maps a Windows executable path to its [Channel].
///
/// Scoop and Chocolatey unpack the app under their own directory, so the
/// executable path identifies the owner — and the owner must run the update
/// rather than the app updating itself behind the manager's back:
///
/// - Scoop apps live under `…\scoop\apps\<name>\…` (the `scoop` segment is the
///   default root for both per-user and global installs; a custom-named
///   `$env:SCOOP` root is not recognized and falls back to the installer
///   channel);
/// - Chocolatey unpacks zip packages under `…\chocolatey\lib\<id>\…`.
///
/// Otherwise it is an Inno Setup installer install (under `…\Programs\KnitCalc\`).
/// winget runs that same installer, so a path check cannot tell the two apart;
/// instead the installer stamps an `install_source` marker next to the exe —
/// `winget` routes to [Channel.windowsWinget] (`winget upgrade`), anything else
/// (a direct install, or a pre-marker install) self-updates via
/// [Channel.windowsManual]. [readInstallSource] is injectable for tests.
Channel windowsChannelForExecutable(
  String executablePath, {
  InstallSourceReader readInstallSource = _readInstallSourceMarker,
}) {
  final normalized = executablePath.toLowerCase().replaceAll('/', '\\');

  if (normalized.contains('\\scoop\\apps\\')) {
    return Channel.windowsScoop;
  }

  if (normalized.contains('\\chocolatey\\lib\\')) {
    return Channel.windowsChocolatey;
  }

  if (readInstallSource(_executableDir(executablePath)) == 'winget') {
    return Channel.windowsWinget;
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
