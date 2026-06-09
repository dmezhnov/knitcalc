/// `dart:io` entry point for [defaultGoogleAuthenticator]: desktop and mobile.
///
/// Desktop and iOS reuse the loopback flow and the shared "Desktop app" OAuth
/// client: desktop opens the external browser, iOS an in-app browser tab that is
/// dismissed after the redirect. Android tries the native account picker
/// (Credential Manager) first and falls back to that same loopback browser flow
/// when the picker is unavailable.
library;

import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'google_oauth.dart';
import 'google_oauth_config.dart';
import 'loopback_oauth_browser.dart';
import 'native_google_sign_in.dart';

GoogleSignInFlow defaultGoogleAuthenticator() {
  final loopback = _loopbackAuthenticator();

  // Android can show the system Google account picker (Credential Manager);
  // fall back to the loopback browser when it isn't available (no Play
  // Services, unregistered signing key, no on-device Google account).
  if (Platform.isAndroid) {
    return NativeFirstGoogleSignInFlow(
      serverClientId: googleServerClientId,
      fallback: loopback,
    );
  }

  return loopback;
}

/// The loopback browser flow shared by desktop and iOS (and Android's fallback).
GoogleSignInFlow _loopbackAuthenticator() {
  final mobile = Platform.isAndroid || Platform.isIOS;

  // Lets the UI abort a sign-in that is waiting on the loopback redirect: the
  // user can close the external consent browser, which fires no callback, so
  // the browser leg races the redirect against this signal.
  final cancelled = Completer<void>();

  return GoogleAuthenticator(
    config: desktopLoopbackConfig(),
    browser: ({required url, required callbackUrlScheme}) =>
        loopbackOAuthBrowser(
          url: url,
          callbackUrlScheme: callbackUrlScheme,
          launchMode: mobile
              ? LaunchMode.inAppBrowserView
              : LaunchMode.externalApplication,
          cancel: cancelled.future,
        ),
    // Mobile opens an in-app tab that must be dismissed; do it after the token
    // exchange so closing it doesn't drop the network mid-request.
    closeBrowser: mobile ? closeInAppWebView : null,
    onCancel: () {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
    },
  );
}
