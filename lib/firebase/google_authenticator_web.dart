/// `dart:js_interop` entry point for [defaultGoogleAuthenticator]: the web.
///
/// Opens the Google consent in a popup. After consent Google redirects the popup
/// to `web/oauth_callback.html` on our origin, which posts the full redirect URL
/// (with the id token in its fragment) back to the opener and closes itself.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'google_oauth.dart';
import 'google_oauth_config.dart';
import 'web_google_sign_in_flow.dart';

GoogleSignInFlow defaultGoogleAuthenticator() {
  // Resolve against the document base URI, not the origin: when the app is
  // served under a sub-path (GitHub Pages uses `--base-href /knitcalc/`) the
  // callback file lives at `<origin>/knitcalc/oauth_callback.html`, and that is
  // also the URI registered for the web OAuth client. Building it from
  // `window.location.origin` would drop the sub-path and send a redirect_uri
  // Google rejects with `redirect_uri_mismatch`. `baseURI` ends in `/`.
  final redirect = '${web.document.baseURI}$webOAuthCallbackPath';

  // Lets the UI abort a sign-in waiting on the popup: closing the popup fires no
  // message, so the browser leg races the redirect against this signal.
  final cancelled = Completer<void>();

  return WebGoogleSignInFlow(
    config: webGoogleConfig(redirect),
    browser: ({required url, required callbackUrlScheme}) =>
        _webPopupOAuthBrowser(
          url: url,
          callbackUrlScheme: callbackUrlScheme,
          cancel: cancelled.future,
        ),
    onCancel: () {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
    },
  );
}

Future<String> _webPopupOAuthBrowser({
  required String url,
  required String callbackUrlScheme,
  Future<void>? cancel,
}) async {
  final origin = web.window.location.origin;
  final completer = Completer<String>();

  final popup = web.window.open(
    url,
    'knitcalc_google_oauth',
    'popup,width=500,height=650',
  );
  if (popup == null) {
    throw const GoogleAuthException('the sign-in popup was blocked');
  }

  void onMessage(web.Event event) {
    final message = event as web.MessageEvent;
    if (message.origin != origin) {
      return;
    }
    final data = message.data;
    if (data == null || !data.isA<JSString>()) {
      return;
    }
    if (!completer.isCompleted) {
      completer.complete((data as JSString).toDart);
    }
  }

  final listener = onMessage.toJS;
  web.window.addEventListener('message', listener);
  if (cancel != null) {
    unawaited(
      cancel.then((_) {
        if (!completer.isCompleted) {
          completer.completeError(const GoogleAuthCancelledException());
        }
      }),
    );
  }
  try {
    return await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw const GoogleAuthException('sign-in timed out'),
    );
  } finally {
    web.window.removeEventListener('message', listener);
    popup.close();
  }
}
