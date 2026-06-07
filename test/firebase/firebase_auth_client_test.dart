import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:knitcalc/firebase/auth_session.dart';
import 'package:knitcalc/firebase/firebase_auth_client.dart';
import 'package:knitcalc/firebase/firebase_config.dart';

void main() {
  const config = FirebaseConfig(projectId: 'proj', apiKey: 'KEY');

  FirebaseAuthClient clientReturning(
    int status,
    Map<String, dynamic> body, {
    void Function(http.Request)? onRequest,
  }) {
    return FirebaseAuthClient(
      config: config,
      httpClient: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  test('signIn parses the session and targets the right endpoint', () async {
    late Uri calledUri;
    late Map<String, dynamic> sentBody;
    final client = clientReturning(
      200,
      {
        'localId': 'uid123',
        'email': 'a@b.com',
        'idToken': 'ID',
        'refreshToken': 'REFRESH',
        'expiresIn': '3600',
      },
      onRequest: (r) {
        calledUri = r.url;
        sentBody = jsonDecode(r.body) as Map<String, dynamic>;
      },
    );

    final session = await client.signIn('a@b.com', 'pw');

    expect(calledUri.path, endsWith('accounts:signInWithPassword'));
    expect(calledUri.queryParameters['key'], 'KEY');
    expect(sentBody['returnSecureToken'], isTrue);
    expect(session.uid, 'uid123');
    expect(session.email, 'a@b.com');
    expect(session.idToken, 'ID');
    expect(session.refreshToken, 'REFRESH');
    expect(session.expiresAt.isAfter(DateTime.now()), isTrue);
  });

  test('signUp hits the signUp endpoint', () async {
    late Uri calledUri;
    final client = clientReturning(200, {
      'localId': 'u',
      'email': 'a@b.com',
      'idToken': 'ID',
      'refreshToken': 'R',
      'expiresIn': '3600',
    }, onRequest: (r) => calledUri = r.url);

    await client.signUp('a@b.com', 'pw');

    expect(calledUri.path, endsWith('accounts:signUp'));
  });

  test('error response throws with the Firebase error code', () async {
    final client = clientReturning(400, {
      'error': {'message': 'EMAIL_EXISTS'},
    });

    await expectLater(
      client.signUp('a@b.com', 'pw'),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'EMAIL_EXISTS',
        ),
      ),
    );
  });

  test('error code is the leading token of a detailed message', () async {
    final client = clientReturning(400, {
      'error': {
        'message': 'WEAK_PASSWORD : Password should be at least 6 chars',
      },
    });

    await expectLater(
      client.signIn('a@b.com', 'x'),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'WEAK_PASSWORD',
        ),
      ),
    );
  });

  test('refresh parses the snake_case secure-token response', () async {
    late Uri calledUri;
    final client = clientReturning(200, {
      'user_id': 'uid123',
      'id_token': 'NEW_ID',
      'refresh_token': 'NEW_REFRESH',
      'expires_in': '3600',
    }, onRequest: (r) => calledUri = r.url);

    final old = AuthSession(
      uid: 'uid123',
      email: 'a@b.com',
      idToken: 'OLD',
      refreshToken: 'OLD_REFRESH',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final session = await client.refresh(old);

    expect(calledUri.host, 'securetoken.googleapis.com');
    expect(session.idToken, 'NEW_ID');
    expect(session.refreshToken, 'NEW_REFRESH');
    expect(
      session.email,
      'a@b.com',
      reason: 'carried over from the old session',
    );
    expect(session.uid, 'uid123');
  });
}
