/// Google OAuth client ids/secrets and the per-platform [GoogleOAuthConfig]
/// builders. Pure data only — no `dart:io`/`dart:js_interop` — so this file is
/// safe to import on every target. The actual browser leg and the choice of
/// flow live behind the conditional import in `default_google_authenticator.dart`.
///
/// Desktop, Android and iOS all reuse the single "Desktop app" OAuth client with
/// a loopback redirect (RFC 8252): the system/in-app browser redirects to
/// `http://localhost:<port>` and our own `HttpServer` catches it. That avoids a
/// per-platform OAuth client (and, on Android, the signing SHA-1). Web needs its
/// own client and an origin redirect, so it has a separate config.
library;

import 'google_oauth.dart';

// Web client auto-created by Firebase for the Google provider.
const String _webClientId =
    '116971646849-m4pm3t1t72afg4525t8jp4phmqmjea59.apps.googleusercontent.com';

/// Server (Web) OAuth client id used as the *audience* of the Google id token
/// obtained via Android Credential Manager (the `serverClientId` handed to
/// `google_sign_in`). It must be the Web client Firebase recognises — the same
/// one as [webGoogleConfig] — so `signInWithIdp` accepts the resulting token.
///
/// Caveat: the native picker only returns a token once an Android OAuth client
/// carrying the app's signing SHA-1 is registered in the same Google Cloud
/// project; until then `authenticate()` fails and the flow falls back to the
/// browser. That registration is a console step, not code.
const String googleServerClientId = _webClientId;

// "Desktop app" OAuth client, shared by desktop and mobile via the loopback
// redirect. The secret is not confidential — it ships inside the app and the
// flow is still protected by PKCE.
const String _desktopClientId =
    '116971646849-ughuudl9f87nkh30v60vbqkdojmcs1d4.apps.googleusercontent.com';
const String _desktopClientSecret = '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';

/// Fixed loopback port for the redirect. Google allows any port for loopback
/// redirects of a desktop client, so a constant keeps the server predictable.
const int desktopLoopbackPort = 8421;

/// Path of the static page that catches the web popup redirect and posts the
/// result back to the opener (served from `web/oauth_callback.html`).
const String webOAuthCallbackPath = 'oauth_callback.html';

/// Config for the loopback flow used by desktop and mobile.
GoogleOAuthConfig desktopLoopbackConfig() {
  const redirect = 'http://localhost:$desktopLoopbackPort';

  return const GoogleOAuthConfig(
    clientId: _desktopClientId,
    clientSecret: _desktopClientSecret,
    redirectUri: redirect,
    callbackUrlScheme: redirect,
  );
}

/// Config for the web implicit flow. [redirectUri] is the app origin plus
/// [webOAuthCallbackPath]; it must be registered in the web OAuth client.
GoogleOAuthConfig webGoogleConfig(String redirectUri) {
  return GoogleOAuthConfig(
    clientId: _webClientId,
    // Implicit flow returns the id token in the fragment; no secret is needed.
    redirectUri: redirectUri,
    callbackUrlScheme: redirectUri,
  );
}
