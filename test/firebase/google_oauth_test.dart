import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:knitcalc/firebase/firebase_auth_client.dart';
import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/firebase/google_oauth.dart';

void main() {
  const config = GoogleOAuthConfig(
    clientId: 'CLIENT.apps.googleusercontent.com',
    clientSecret: 'SECRET',
    redirectUri: 'http://localhost:8421',
    callbackUrlScheme: 'http://localhost:8421',
  );

  group('PKCE', () {
    test('verifier is url-safe and within the RFC length bounds', () {
      final verifier = generateCodeVerifier();

      expect(verifier.length, inInclusiveRange(43, 128));
      expect(verifier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('challenge is unpadded base64url of the verifier sha256', () {
      // Known vector from RFC 7636 appendix B.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

      expect(
        codeChallengeS256(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });
  });

  test('buildGoogleAuthUrl carries the PKCE and client params', () {
    final url = buildGoogleAuthUrl(
      config: config,
      codeChallenge: 'CHAL',
      state: 'STATE',
    );

    expect(url.host, 'accounts.google.com');
    final q = url.queryParameters;
    expect(q['client_id'], config.clientId);
    expect(q['redirect_uri'], config.redirectUri);
    expect(q['response_type'], 'code');
    expect(q['code_challenge'], 'CHAL');
    expect(q['code_challenge_method'], 'S256');
    expect(q['state'], 'STATE');
    expect(q['scope'], contains('email'));
  });

  group('GoogleAuthenticator.obtainIdToken', () {
    GoogleAuthenticator authenticator({
      required OAuthBrowser browser,
      required MockClientHandler exchange,
    }) {
      return GoogleAuthenticator(
        config: config,
        browser: browser,
        httpClient: MockClient(exchange),
      );
    }

    test('runs the flow and returns the Google id token', () async {
      late Map<String, String> exchangeBody;
      final auth = authenticator(
        browser: ({required url, required callbackUrlScheme}) async {
          final state = Uri.parse(url).queryParameters['state'];
          return 'http://localhost:8421/?code=AUTH_CODE&state=$state';
        },
        exchange: (request) async {
          exchangeBody = Uri.splitQueryString(request.body);
          return http.Response(jsonEncode({'id_token': 'GOOGLE_ID'}), 200);
        },
      );

      final idToken = await auth.obtainIdToken();

      expect(idToken, 'GOOGLE_ID');
      expect(exchangeBody['code'], 'AUTH_CODE');
      expect(exchangeBody['grant_type'], 'authorization_code');
      expect(exchangeBody['code_verifier'], isNotEmpty);
      expect(exchangeBody['redirect_uri'], config.redirectUri);
    });

    test('rejects a mismatched state (CSRF guard)', () async {
      final auth = authenticator(
        browser: ({required url, required callbackUrlScheme}) async =>
            'http://localhost:8421/?code=X&state=WRONG',
        exchange: (request) async => http.Response('{}', 200),
      );

      await expectLater(
        auth.obtainIdToken(),
        throwsA(isA<GoogleAuthException>()),
      );
    });

    test(
      'throws when the redirect carries an error instead of a code',
      () async {
        final auth = authenticator(
          browser: ({required url, required callbackUrlScheme}) async {
            final state = Uri.parse(url).queryParameters['state'];
            return 'http://localhost:8421/?error=access_denied&state=$state';
          },
          exchange: (request) async => http.Response('{}', 200),
        );

        await expectLater(
          auth.obtainIdToken(),
          throwsA(isA<GoogleAuthException>()),
        );
      },
    );
  });

  test('FirebaseAuthClient.signInWithGoogle posts the IdP body', () async {
    late Map<String, dynamic> body;
    final client = FirebaseAuthClient(
      config: const FirebaseConfig(projectId: 'p', apiKey: 'K'),
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'localId': 'uid1',
            'email': 'a@gmail.com',
            'idToken': 'FB_ID',
            'refreshToken': 'R',
            'expiresIn': '3600',
            'emailVerified': true,
            'photoUrl': 'https://lh3.googleusercontent.com/a/pic',
          }),
          200,
        );
      }),
    );

    final session = await client.signInWithGoogle(
      googleIdToken: 'GOOGLE_ID',
      requestUri: 'http://localhost:8421',
    );

    expect(body['postBody'], contains('id_token=GOOGLE_ID'));
    expect(body['postBody'], contains('providerId=google.com'));
    expect(session.uid, 'uid1');
    expect(session.emailVerified, isTrue);
    expect(session.photoUrl, 'https://lh3.googleusercontent.com/a/pic');
  });
}
