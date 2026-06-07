/// Loopback [OAuthBrowser] for the `dart:io` platforms (desktop and mobile):
/// opens a browser for the OAuth consent step and catches the redirect to
/// `http://localhost:<port>` with a one-shot local server.
///
/// This needs no webview/native auth plugin, so the Linux/Windows build pulls in
/// no extra system libraries (only `url_launcher`). On desktop the consent opens
/// in the external browser; on mobile it opens an in-app browser tab so the app
/// stays foregrounded (and its server alive) while the redirect happens, then
/// the tab is dismissed.
library;

import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'google_oauth.dart';

/// Page shown in the browser tab after the redirect, telling the user to return.
const String _landingPage =
    '<!DOCTYPE html><html><head><meta charset="utf-8">'
    '<title>KnitCalc</title></head><body style="font-family:sans-serif;'
    'text-align:center;padding-top:3em">'
    '<h2>Готово</h2><p>Можно закрыть эту вкладку и вернуться в KnitCalc.</p>'
    '</body></html>';

/// Binds a local server on the [callbackUrlScheme] port, opens [url] in the
/// browser, and resolves with the full redirect URL once Google calls back.
///
/// [launchMode] selects the external browser (desktop) or an in-app tab
/// (mobile); when [closeInAppViewAfter] is set the in-app tab is dismissed once
/// the redirect is captured.
Future<String> loopbackOAuthBrowser({
  required String url,
  required String callbackUrlScheme,
  LaunchMode launchMode = LaunchMode.externalApplication,
  bool closeInAppViewAfter = false,
}) async {
  final callback = Uri.parse(callbackUrlScheme);
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    callback.port,
  );

  try {
    final launched = await launchUrl(Uri.parse(url), mode: launchMode);
    if (!launched) {
      throw const GoogleAuthException('could not open the browser');
    }

    final request = await server.first.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw const GoogleAuthException('sign-in timed out'),
    );
    final result = request.requestedUri.toString();

    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_landingPage);
    await request.response.close();

    if (closeInAppViewAfter) {
      await closeInAppWebView();
    }

    return result;
  } finally {
    await server.close(force: true);
  }
}
