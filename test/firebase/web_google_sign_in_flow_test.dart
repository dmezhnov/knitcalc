import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:knitcalc/firebase/google_oauth.dart';
import 'package:knitcalc/firebase/web_google_sign_in_flow.dart';

void main() {
  const config = GoogleOAuthConfig(
    clientId: 'WEB.apps.googleusercontent.com',
    redirectUri: 'https://app.example/oauth_callback.html',
    callbackUrlScheme: 'https://app.example/oauth_callback.html',
  );

  WebGoogleSignInFlow flow(OAuthBrowser browser) =>
      WebGoogleSignInFlow(config: config, browser: browser);

  test(
    'requests the implicit flow and returns the fragment id token',
    () async {
      late Uri authUrl;
      final result = flow(({required url, required callbackUrlScheme}) async {
        authUrl = Uri.parse(url);
        final state = authUrl.queryParameters['state'];
        return '${config.redirectUri}#id_token=GOOGLE_ID&state=$state';
      });

      final idToken = await result.obtainIdToken();

      expect(idToken, 'GOOGLE_ID');
      expect(authUrl.queryParameters['response_type'], 'id_token');
      expect(authUrl.queryParameters['nonce'], isNotEmpty);
      expect(authUrl.queryParameters['redirect_uri'], config.redirectUri);
      // No PKCE challenge in the implicit flow.
      expect(authUrl.queryParameters.containsKey('code_challenge'), isFalse);
    },
  );

  test('rejects a mismatched state (CSRF guard)', () async {
    final result = flow(
      ({required url, required callbackUrlScheme}) async =>
          '${config.redirectUri}#id_token=X&state=WRONG',
    );

    await expectLater(
      result.obtainIdToken(),
      throwsA(isA<GoogleAuthException>()),
    );
  });

  test('cancel aborts a pending obtainIdToken via onCancel', () async {
    final cancelled = Completer<void>();
    final result = WebGoogleSignInFlow(
      config: config,
      browser: ({required url, required callbackUrlScheme}) async {
        await cancelled.future;
        throw const GoogleAuthCancelledException();
      },
      onCancel: () {
        if (!cancelled.isCompleted) {
          cancelled.complete();
        }
      },
    );

    final pending = result.obtainIdToken();
    result.cancel();

    await expectLater(pending, throwsA(isA<GoogleAuthCancelledException>()));
  });

  test('throws when the fragment carries an error', () async {
    final result = flow(({required url, required callbackUrlScheme}) async {
      final state = Uri.parse(url).queryParameters['state'];
      return '${config.redirectUri}#error=access_denied&state=$state';
    });

    await expectLater(
      result.obtainIdToken(),
      throwsA(isA<GoogleAuthException>()),
    );
  });
}
