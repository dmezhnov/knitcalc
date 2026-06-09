/// Detects and helps remove a leftover install of the pre-rename Android app.
///
/// The app id changed from `com.example.knitcalc` to `io.github.dmezhnov.knitcalc`
/// (see [legacyAndroidPackage]). Android treats a different applicationId as a
/// separate app, so updating to the renamed build installs *alongside* the old
/// one instead of replacing it. We can detect the old package and open the
/// system uninstall dialog, but Android forbids silently removing another app —
/// the user confirms in the system UI.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The applicationId the app shipped under before the rename.
const String legacyAndroidPackage = 'com.example.knitcalc';

/// Method channel shared with `MainActivity` (also used by the updater).
const MethodChannel _channel = MethodChannel('knitcalc/android_update');

/// Whether the pre-rename app is still installed on this Android device.
/// Always false off Android (and on web), and on any host/channel error.
Future<bool> legacyAppInstalled() async {
  if (kIsWeb || !Platform.isAndroid) {
    return false;
  }

  try {
    final installed = await _channel.invokeMethod<bool>('isPackageInstalled', {
      'package': legacyAndroidPackage,
    });

    return installed ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Opens the system uninstall dialog for the pre-rename app. The user confirms
/// (or cancels) the removal in the system UI; this returns once it is launched.
Future<void> uninstallLegacyApp() async {
  if (kIsWeb || !Platform.isAndroid) {
    return;
  }

  await _channel.invokeMethod<void>('uninstallPackage', {
    'package': legacyAndroidPackage,
  });
}
