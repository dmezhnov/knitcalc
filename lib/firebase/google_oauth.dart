/// Google OAuth 2.0 (authorization code + PKCE) used to obtain a Google
/// `id_token`, which Firebase then exchanges for a session via
/// [FirebaseAuthClient.signInWithIdp].
///
/// The browser leg is abstracted behind [OAuthBrowser] so the rest of the flow
/// (PKCE, URL building, token exchange) is pure and unit-testable. Per-platform
/// OAuth client ids and redirect handling live in [GoogleOAuthConfig].
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Opens [url] in a browser and resolves with the full redirect URL (containing
/// the authorization `code`) once the OAuth provider redirects to
/// [callbackUrlScheme]. Wraps `FlutterWebAuth2.authenticate` in production.
typedef OAuthBrowser =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
    });

/// Per-platform Google OAuth settings. Each platform needs its own OAuth client
/// (Google requirement) and redirects differently: a loopback `http://localhost`
/// server on Linux/Windows, a custom scheme on Apple/Android, an origin redirect
/// on web.
class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.clientId,
    required this.redirectUri,
    required this.callbackUrlScheme,
    this.clientSecret,
  });

  /// OAuth 2.0 client id for the current platform.
  final String clientId;

  /// Client secret, when the platform's client type has one (desktop/web).
  /// Native mobile clients use PKCE only and leave this null.
  final String? clientSecret;

  /// Redirect URI registered for the client and sent in the auth/token requests.
  final String redirectUri;

  /// Scheme handed to the browser plugin to detect the redirect back.
  final String callbackUrlScheme;
}

/// A random high-entropy PKCE code verifier (RFC 7636), 43–128 url-safe chars.
String generateCodeVerifier([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(64, (_) => rng.nextInt(256));

  return _base64Url(bytes);
}

/// The S256 PKCE challenge for [verifier]: base64url(sha256(verifier)).
String codeChallengeS256(String verifier) =>
    _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

/// Builds the Google authorization endpoint URL.
///
/// Defaults to the authorization-code flow (desktop/mobile, with a PKCE
/// [codeChallenge]); pass `responseType: 'id_token'` plus a [nonce] for the web
/// implicit flow, which returns the id token in the redirect fragment without a
/// token-endpoint exchange (so no client secret is shipped to the browser).
Uri buildGoogleAuthUrl({
  required GoogleOAuthConfig config,
  required String state,
  String responseType = 'code',
  String? codeChallenge,
  String? nonce,
  List<String> scopes = const ['openid', 'email', 'profile'],
}) {
  final params = <String, String>{
    'client_id': config.clientId,
    'redirect_uri': config.redirectUri,
    'response_type': responseType,
    'scope': scopes.join(' '),
    'state': state,
    'prompt': 'select_account',
  };
  if (codeChallenge != null) {
    params['code_challenge'] = codeChallenge;
    params['code_challenge_method'] = 'S256';
  }
  if (nonce != null) {
    params['nonce'] = nonce;
  }

  return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', params);
}

/// A platform's Google sign-in flow: yields a Google `id_token` that Firebase
/// exchanges for a session. The desktop/mobile implementation is
/// [GoogleAuthenticator] (code+PKCE); web uses an implicit-flow variant.
abstract interface class GoogleSignInFlow {
  GoogleOAuthConfig get config;

  /// Runs the sign-in and returns the Google `id_token`, or throws
  /// [GoogleAuthException] on cancellation or failure.
  Future<String> obtainIdToken();

  /// Aborts an in-flight [obtainIdToken]: the pending call completes with a
  /// [GoogleAuthCancelledException]. Used when the user closes the consent
  /// browser, which fires no redirect and gives the app no other signal.
  void cancel();
}

/// Drives the Google sign-in flow and returns the Google `id_token`.
class GoogleAuthenticator implements GoogleSignInFlow {
  GoogleAuthenticator({
    required this.config,
    required this.browser,
    this.closeBrowser,
    this.onCancel,
    http.Client? httpClient,
    Random? random,
  }) : _http = httpClient ?? http.Client(),
       _random = random ?? Random.secure();

  @override
  final GoogleOAuthConfig config;
  final OAuthBrowser browser;

  /// Aborts the browser leg when [cancel] is called. The loopback flow wires
  /// this to a signal it races against the redirect (see the io entry point);
  /// null when the platform has nothing to interrupt.
  final void Function()? onCancel;

  /// Dismisses the consent browser once the redirect is captured, if the
  /// platform opened an in-app one (mobile). Called *before* the token
  /// exchange: while the in-app tab is up the app is backgrounded and can't
  /// resolve `oauth2.googleapis.com` ("Failed host lookup"), so the app must
  /// return to the foreground first. The resume still takes a second or two to
  /// settle, which the retry in [_exchangeCode] rides out. Null on
  /// desktop/web, where nothing needs closing.
  final Future<void> Function()? closeBrowser;

  final http.Client _http;
  final Random _random;

  /// Runs the browser consent, exchanges the returned code, and yields the
  /// Google id token. Throws [GoogleAuthException] on cancellation or failure.
  @override
  Future<String> obtainIdToken() async {
    final verifier = generateCodeVerifier(_random);
    final state = generateCodeVerifier(_random);

    final url = buildGoogleAuthUrl(
      config: config,
      codeChallenge: codeChallengeS256(verifier),
      state: state,
    );

    final redirect = await browser(
      url: url.toString(),
      callbackUrlScheme: config.callbackUrlScheme,
    );

    // Redirect captured. Dismiss the in-app tab first so the app returns to the
    // foreground before the token exchange (see [closeBrowser]): a backgrounded
    // app can't resolve oauth2.googleapis.com. The resume then settles over a
    // second or two, which the retry in [_exchangeCode] rides out.
    await closeBrowser?.call();

    final params = Uri.parse(redirect).queryParameters;
    final code = params['code'];

    if (params['state'] != state) {
      throw const GoogleAuthException('state mismatch');
    }
    if (code == null) {
      throw GoogleAuthException(params['error'] ?? 'no authorization code');
    }

    return _exchangeCode(code, verifier);
  }

  @override
  void cancel() => onCancel?.call();

  Future<String> _exchangeCode(String code, String verifier) async {
    final response = await _postWithRetry(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
        if (config.clientSecret != null) 'client_secret': config.clientSecret!,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': config.redirectUri,
      },
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw GoogleAuthException(
        json['error']?.toString() ?? 'token exchange failed',
      );
    }

    final idToken = json['id_token'] as String?;
    if (idToken == null) {
      throw const GoogleAuthException('no id_token in token response');
    }

    return idToken;
  }

  /// POSTs with retries on transient transport failures.
  ///
  /// On Android the code-for-token exchange fires just as the in-app browser
  /// tab is dismissed and the app activity resumes; until the resume settles
  /// the app still can't reach the network — DNS returns no address ("Failed
  /// host lookup", errno 7) or the socket is aborted ("Software caused
  /// connection abort", errno 103), both surfaced by `package:http` as a
  /// [http.ClientException]. The resume can take a couple of seconds, so the
  /// backoffs span ~7s total to ride it out. [http.ClientException] is caught
  /// (rather than `SocketException`) to keep this file free of `dart:io` so the
  /// web build still compiles.
  Future<http.Response> _postWithRetry(
    Uri url, {
    required Map<String, String> headers,
    required Map<String, String> body,
  }) async {
    const delays = [
      Duration(milliseconds: 400),
      Duration(milliseconds: 800),
      Duration(milliseconds: 1500),
      Duration(milliseconds: 2000),
      Duration(milliseconds: 2500),
    ];

    for (var attempt = 0; ; attempt++) {
      try {
        return await _http.post(url, headers: headers, body: body);
      } on http.ClientException {
        if (attempt >= delays.length) {
          rethrow;
        }
        await Future<void>.delayed(delays[attempt]);
      }
    }
  }
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => 'GoogleAuthException($message)';
}

/// Sign-in aborted before completing — the user closed the consent browser or
/// [GoogleSignInFlow.cancel] was called. A subtype of [GoogleAuthException] so
/// existing `catch`/`throwsA` sites still match, while the UI can single it out
/// and treat it as a silent cancel rather than a failure.
class GoogleAuthCancelledException extends GoogleAuthException {
  const GoogleAuthCancelledException() : super('sign-in cancelled');
}

/// base64url without padding, as required for PKCE values.
String _base64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
