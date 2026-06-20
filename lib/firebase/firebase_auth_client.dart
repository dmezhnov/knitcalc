/// Stateless REST wrapper over the Firebase Auth endpoints (Identity Toolkit for
/// sign-up/sign-in, Secure Token for refresh).
///
/// It holds no session of its own: every call returns an [AuthSession] that the
/// caller is responsible for persisting. The [http.Client] is injectable so the
/// parsing and error mapping can be unit-tested without real network access.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'firebase_config.dart';

/// Raised when a Firebase Auth REST call fails. [code] is the raw Firebase error
/// code (e.g. `EMAIL_EXISTS`, `INVALID_LOGIN_CREDENTIALS`, `EMAIL_NOT_FOUND`),
/// which the UI maps to a localized message.
class FirebaseAuthException implements Exception {
  const FirebaseAuthException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'FirebaseAuthException($code)';
}

class FirebaseAuthClient {
  FirebaseAuthClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final FirebaseConfig config;
  final http.Client _http;

  /// Per-request deadline, so sign-in and the lazy token refresh can't stall
  /// indefinitely on a blocked/blackholed network. Injectable for tests.
  final Duration timeout;

  static const String _identityBase =
      'https://identitytoolkit.googleapis.com/v1';
  static const String _tokenBase = 'https://securetoken.googleapis.com/v1';

  /// Registers a new account and returns its session.
  Future<AuthSession> signUp(String email, String password) =>
      _passwordCall('accounts:signUp', email, password);

  /// Signs in an existing account and returns its session.
  Future<AuthSession> signIn(String email, String password) =>
      _passwordCall('accounts:signInWithPassword', email, password);

  Future<AuthSession> _passwordCall(
    String method,
    String email,
    String password,
  ) async {
    final json = await _post('$_identityBase/$method?key=${config.apiKey}', {
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });

    return AuthSession.fromSignInResponse(json);
  }

  /// Exchanges the session's refresh token for one with a fresh id token. The
  /// email and verification flag are carried over since the refresh response
  /// does not include them.
  Future<AuthSession> refresh(AuthSession session) async {
    final json = await _post('$_tokenBase/token?key=${config.apiKey}', {
      'grant_type': 'refresh_token',
      'refresh_token': session.refreshToken,
    });

    return AuthSession.fromRefreshResponse(
      json,
      email: session.email,
      emailVerified: session.emailVerified,
      photoUrl: session.photoUrl,
    );
  }

  /// Exchanges a Google `id_token` for a Firebase session via the identity
  /// provider endpoint. Google accounts come back with `emailVerified: true`,
  /// so they skip the email-verification gate.
  Future<AuthSession> signInWithGoogle({
    required String googleIdToken,
    required String requestUri,
  }) async {
    final json = await _post(
      '$_identityBase/accounts:signInWithIdp?key=${config.apiKey}',
      {
        'postBody': 'id_token=$googleIdToken&providerId=google.com',
        'requestUri': requestUri,
        'returnSecureToken': true,
        'returnIdpCredential': true,
      },
    );

    return AuthSession.fromSignInResponse(json);
  }

  /// Sends the account a verification email for the user holding [idToken].
  Future<void> sendVerificationEmail(String idToken) async {
    await _post('$_identityBase/accounts:sendOobCode?key=${config.apiKey}', {
      'requestType': 'VERIFY_EMAIL',
      'idToken': idToken,
    });
  }

  /// Sends a password-reset email to [email] (no sign-in required).
  Future<void> sendPasswordReset(String email) async {
    await _post('$_identityBase/accounts:sendOobCode?key=${config.apiKey}', {
      'requestType': 'PASSWORD_RESET',
      'email': email,
    });
  }

  /// Looks up the current `emailVerified` state for the user holding [idToken].
  Future<bool> fetchEmailVerified(String idToken) async =>
      (await lookupAccount(idToken)).emailVerified;

  /// Looks up the current profile for the user holding [idToken]: the
  /// verification flag, the avatar URL, and whether the account is federated
  /// through Google (so callers know the avatar is provider-managed).
  Future<({bool emailVerified, String? photoUrl, bool isGoogle})> lookupAccount(
    String idToken,
  ) async {
    final json = await _post(
      '$_identityBase/accounts:lookup?key=${config.apiKey}',
      {'idToken': idToken},
    );

    final users = json['users'];
    if (users is! List || users.isEmpty || users.first is! Map) {
      return (emailVerified: false, photoUrl: null, isGoogle: false);
    }

    final user = users.first as Map;
    final providers = user['providerUserInfo'];
    final isGoogle =
        providers is List &&
        providers.any((p) => p is Map && p['providerId'] == 'google.com');

    return (
      emailVerified: user['emailVerified'] as bool? ?? false,
      photoUrl: user['photoUrl'] as String?,
      isGoogle: isGoogle,
    );
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body,
  ) async {
    final response = await _http
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    // A blocked/intercepting network can answer with a non-JSON page (an ISP or
    // GFE block page); surface that as a FirebaseAuthException rather than
    // letting a raw FormatException escape to callers.
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object {
      throw FirebaseAuthException(
        'UNKNOWN_ERROR',
        'Unexpected response (HTTP ${response.statusCode})',
      );
    }

    if (response.statusCode >= 400) {
      final error = json['error'];
      // Firebase returns e.g. {"error":{"message":"WEAK_PASSWORD : Password
      // should be at least 6 characters"}}; keep the leading code token.
      final raw = error is Map ? error['message']?.toString() : null;
      final code = (raw ?? 'UNKNOWN_ERROR').split(' ').first;

      throw FirebaseAuthException(code, raw);
    }

    return json;
  }
}
