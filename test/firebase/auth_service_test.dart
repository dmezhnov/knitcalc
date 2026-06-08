import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/firebase/auth_service.dart';
import 'package:knitcalc/firebase/auth_session.dart';
import 'package:knitcalc/firebase/firebase_auth_client.dart';
import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/firebase/google_oauth.dart';

/// Records how an AuthService's auth client was exercised.
class Calls {
  int refreshes = 0;
  int verifyEmails = 0;
  String? lastOobType;
  String? lastOobEmail;
  bool verified = false;

  /// What the mocked `accounts:lookup` reports back for the profile.
  String? lookupPhotoUrl;
  bool lookupIsGoogle = false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({AuthService service, Calls calls}) build() {
    final calls = Calls();
    final client = FirebaseAuthClient(
      config: const FirebaseConfig(projectId: 'p', apiKey: 'K'),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;

        if (path.endsWith('accounts:signUp') ||
            path.endsWith('accounts:signInWithPassword')) {
          return http.Response(
            jsonEncode({
              'localId': 'uid1',
              'email': 'a@b.com',
              'idToken': 'ID1',
              'refreshToken': 'R1',
              'expiresIn': '3600',
            }),
            200,
          );
        }
        if (path.endsWith('accounts:sendOobCode')) {
          calls.lastOobType = body['requestType'] as String?;
          calls.lastOobEmail = body['email'] as String?;
          if (calls.lastOobType == 'VERIFY_EMAIL') calls.verifyEmails++;
          return http.Response('{}', 200);
        }
        if (path.endsWith('accounts:signInWithIdp')) {
          return http.Response(
            jsonEncode({
              'localId': 'guid',
              'email': 'g@gmail.com',
              'idToken': 'GFB',
              'refreshToken': 'GR',
              'expiresIn': '3600',
              'emailVerified': true,
            }),
            200,
          );
        }
        if (path.endsWith('accounts:lookup')) {
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'emailVerified': calls.verified,
                  if (calls.lookupPhotoUrl != null)
                    'photoUrl': calls.lookupPhotoUrl,
                  if (calls.lookupIsGoogle)
                    'providerUserInfo': [
                      {'providerId': 'google.com'},
                    ],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'securetoken.googleapis.com') {
          calls.refreshes++;
          return http.Response(
            jsonEncode({
              'user_id': 'uid1',
              'id_token': 'ID2',
              'refresh_token': 'R2',
              'expires_in': '3600',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    return (service: AuthService(client: client), calls: calls);
  }

  test('signIn persists the session and survives a restart', () async {
    final service = build().service;
    var notified = 0;
    service.addListener(() => notified++);

    await service.signIn('a@b.com', 'pw');

    expect(service.isSignedIn, isTrue);
    expect(service.uid, 'uid1');
    expect(notified, greaterThan(0));

    final restarted = build().service;
    await restarted.init();
    expect(restarted.isSignedIn, isTrue);
    expect(restarted.email, 'a@b.com');
  });

  test(
    'freshIdToken returns the token without refreshing when valid',
    () async {
      final built = build();
      await built.service.signIn('a@b.com', 'pw');

      expect(await built.service.freshIdToken(), 'ID1');
      expect(built.calls.refreshes, 0);
    },
  );

  test('freshIdToken refreshes a near-expiry token', () async {
    final expired = AuthSession(
      uid: 'uid1',
      email: 'a@b.com',
      idToken: 'OLD',
      refreshToken: 'R1',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    SharedPreferences.setMockInitialValues({
      'auth_session': jsonEncode(expired.toJson()),
    });

    final built = build();
    await built.service.init();

    expect(await built.service.freshIdToken(), 'ID2');
    expect(built.calls.refreshes, 1);
  });

  test('signOut clears the session and persistence', () async {
    final service = build().service;
    await service.signIn('a@b.com', 'pw');

    await service.signOut();

    expect(service.isSignedIn, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_session'), isNull);
  });

  test('signUp sends a verification email', () async {
    final built = build();

    await built.service.signUp('a@b.com', 'pw');

    expect(built.service.isSignedIn, isTrue);
    expect(built.service.emailVerified, isFalse);
    expect(built.calls.verifyEmails, 1);
    expect(built.calls.lastOobType, 'VERIFY_EMAIL');
  });

  test('signIn reflects the verified state from lookup', () async {
    final built = build();
    built.calls.verified = true;

    await built.service.signIn('a@b.com', 'pw');

    expect(built.service.emailVerified, isTrue);
  });

  test('sendPasswordReset asks for a reset email', () async {
    final built = build();

    await built.service.sendPasswordReset('reset@b.com');

    expect(built.calls.lastOobType, 'PASSWORD_RESET');
    expect(built.calls.lastOobEmail, 'reset@b.com');
  });

  test(
    'signInWithGoogle exchanges a Google token for a verified session',
    () async {
      final built = build();
      final authenticator = GoogleAuthenticator(
        config: const GoogleOAuthConfig(
          clientId: 'C',
          redirectUri: 'http://localhost:8421',
          callbackUrlScheme: 'http://localhost:8421',
        ),
        browser: ({required url, required callbackUrlScheme}) async {
          final state = Uri.parse(url).queryParameters['state'];
          return 'http://localhost:8421/?code=CODE&state=$state';
        },
        httpClient: MockClient(
          (request) async => http.Response(jsonEncode({'id_token': 'G'}), 200),
        ),
      );

      await built.service.signInWithGoogle(authenticator: authenticator);

      expect(built.service.isSignedIn, isTrue);
      expect(built.service.uid, 'guid');
      expect(built.service.emailVerified, isTrue);
    },
  );

  test('reloadEmailVerified updates the session when confirmed', () async {
    final built = build();
    await built.service.signIn('a@b.com', 'pw');
    expect(built.service.emailVerified, isFalse);

    built.calls.verified = true;
    final verified = await built.service.reloadEmailVerified();

    expect(verified, isTrue);
    expect(built.service.emailVerified, isTrue);
  });

  GoogleSignInFlow googleAuthenticator() => GoogleAuthenticator(
    config: const GoogleOAuthConfig(
      clientId: 'C',
      redirectUri: 'http://localhost:8421',
      callbackUrlScheme: 'http://localhost:8421',
    ),
    browser: ({required url, required callbackUrlScheme}) async {
      final state = Uri.parse(url).queryParameters['state'];
      return 'http://localhost:8421/?code=CODE&state=$state';
    },
    httpClient: MockClient(
      (request) async => http.Response(jsonEncode({'id_token': 'G'}), 200),
    ),
  );

  test('refreshProfile updates a changed Google avatar', () async {
    final built = build();
    await built.service.signInWithGoogle(authenticator: googleAuthenticator());
    expect(built.service.photoUrl, isNull);

    built.calls
      ..lookupIsGoogle = true
      ..lookupPhotoUrl = 'https://lh3.googleusercontent.com/new';

    var notified = 0;
    built.service.addListener(() => notified++);

    await built.service.refreshProfile();

    expect(built.service.photoUrl, 'https://lh3.googleusercontent.com/new');
    expect(notified, greaterThan(0));
  });

  test('refreshProfile leaves a password account avatar untouched', () async {
    final built = build();
    await built.service.signIn('a@b.com', 'pw');

    // A non-Google lookup must not adopt a stray avatar onto the account.
    built.calls
      ..lookupIsGoogle = false
      ..lookupPhotoUrl = 'https://example.com/should-be-ignored';

    await built.service.refreshProfile();

    expect(built.service.photoUrl, isNull);
  });
}
