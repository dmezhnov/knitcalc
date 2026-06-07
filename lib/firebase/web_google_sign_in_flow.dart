/// Web Google sign-in via the OpenID Connect implicit flow.
///
/// The browser is redirected to Google with `response_type=id_token`; Google
/// returns the id token directly in the redirect fragment, so there is no
/// token-endpoint exchange (and thus no client secret in the browser and no
/// CORS call). The browser leg is abstracted behind [OAuthBrowser] so this whole
/// flow is pure and unit-testable on the VM; the real popup wiring lives in
/// `google_authenticator_web.dart`.
library;

import 'dart:math';

import 'google_oauth.dart';

class WebGoogleSignInFlow implements GoogleSignInFlow {
  WebGoogleSignInFlow({
    required this.config,
    required this.browser,
    Random? random,
  }) : _random = random ?? Random.secure();

  @override
  final GoogleOAuthConfig config;

  final OAuthBrowser browser;
  final Random _random;

  @override
  Future<String> obtainIdToken() async {
    final state = generateCodeVerifier(_random);
    final nonce = generateCodeVerifier(_random);

    final url = buildGoogleAuthUrl(
      config: config,
      state: state,
      responseType: 'id_token',
      nonce: nonce,
    );

    final redirect = await browser(
      url: url.toString(),
      callbackUrlScheme: config.callbackUrlScheme,
    );

    // The implicit flow returns its parameters in the URL fragment, not the
    // query string.
    final params = Uri.splitQueryString(Uri.parse(redirect).fragment);

    if (params['state'] != state) {
      throw const GoogleAuthException('state mismatch');
    }

    final idToken = params['id_token'];
    if (idToken == null) {
      throw GoogleAuthException(params['error'] ?? 'no id_token in redirect');
    }

    return idToken;
  }
}
