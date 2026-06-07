/// `dart:io` entry point for [defaultGoogleAuthenticator]: desktop and mobile.
///
/// All four reuse the loopback flow and the shared "Desktop app" OAuth client.
/// Desktop opens the external browser; mobile opens an in-app browser tab so the
/// app (and its loopback server) stays alive, then dismisses the tab.
library;

import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'google_oauth.dart';
import 'google_oauth_config.dart';
import 'loopback_oauth_browser.dart';

GoogleSignInFlow defaultGoogleAuthenticator() {
  final mobile = Platform.isAndroid || Platform.isIOS;

  return GoogleAuthenticator(
    config: desktopLoopbackConfig(),
    browser: ({required url, required callbackUrlScheme}) =>
        loopbackOAuthBrowser(
          url: url,
          callbackUrlScheme: callbackUrlScheme,
          launchMode: mobile
              ? LaunchMode.inAppBrowserView
              : LaunchMode.externalApplication,
        ),
    // Mobile opens an in-app tab that must be dismissed; do it after the token
    // exchange so closing it doesn't drop the network mid-request.
    closeBrowser: mobile ? closeInAppWebView : null,
  );
}
