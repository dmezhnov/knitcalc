import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:knitcalc/l10n/app_localizations.dart';

/// Shared with the native side (see `android_update_service_io.dart` and
/// `MainActivity`). Naming a [MethodChannel] is platform-agnostic; the call is
/// simply unhandled off Android.
const MethodChannel _channel = MethodChannel('knitcalc/android_update');

/// Pushes the app's currently selected language into the native download
/// notification, so it follows the in-app language toggle rather than the device
/// locale. The native side keeps the latest set and uses it when building the
/// notification (falling back to its bundled, device-locale strings if never
/// set). No-op on every platform but Android.
///
/// Call this wherever the active [AppLocalizations] is available and on every
/// locale change (a [State.didChangeDependencies] is a good hook), so a download
/// that later goes to the background shows its notification in the chosen
/// language.
Future<void> syncAndroidUpdateNotificationStrings(AppLocalizations l10n) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    await _channel.invokeMethod<void>('setNotificationStrings', {
      'title': l10n.updateDownloadTitle,
      'preparing': l10n.updatePreparing,
      'paused': l10n.updatePaused,
      'pause': l10n.updatePause,
      'resume': l10n.updateResume,
      'cancel': l10n.cancelAction,
      'mbUnit': l10n.byteUnitMB,
      'readyTitle': l10n.updateDownloadedTitle,
      'readyText': l10n.updateTapToInstall,
    });
  } on PlatformException {
    // Older native side without the handler: it keeps its bundled strings.
  } on MissingPluginException {
    // No handler on this platform.
  }
}
