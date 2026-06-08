import 'package:knitcalc/update/app_version.dart';

/// What the user should do with a found update.
enum UpdateAction {
  /// The update is installed by the platform from inside the app
  /// (Play in-app update, Sparkle/WinSparkle, service worker reload).
  inApp,

  /// An external page must be opened: a store or a GitHub Release.
  openUrl,

  /// A package manager owns the update: run its upgrade command (e.g.
  /// `winget upgrade`, `brew upgrade --cask`) in a visible terminal, then quit
  /// so the manager can replace the running files. No in-app download.
  runCommand,

  /// Updates are managed by an external daemon (snap/flatpak) or by the store
  /// itself — there is nothing for the app to do.
  managedExternally,
}

/// Description of an available update, returned by `UpdateService.checkForUpdate`.
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.action,
    this.versionLabel,
    this.releaseNotes,
    this.url,
    this.downloadSize,
    this.mandatory = false,
  });

  /// Version available in the update source.
  final AppVersion latestVersion;

  /// Human-readable version shown in the banner (e.g. "1.9.0"). `null` when the
  /// source exposes no marketing version (Play only reports a numeric version
  /// code, RuStore none at all); the banner then shows a generic message.
  final String? versionLabel;

  /// How to deliver the update to the user.
  final UpdateAction action;

  /// Release notes (markdown/plain), if the source provides them.
  final String? releaseNotes;

  /// Link for `UpdateAction.openUrl` (store/release page/artifact).
  final String? url;

  /// Size of the downloadable payload in bytes, when the source reports it.
  /// Shown in the update banner so the user knows how much will be fetched.
  final int? downloadSize;

  /// Whether the update is mandatory (blocking dialog instead of a banner).
  final bool mandatory;

  @override
  String toString() =>
      'UpdateInfo($latestVersion, $action, mandatory: $mandatory)';
}
