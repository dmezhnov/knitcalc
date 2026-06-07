/// Owns the current [AuthSession] and notifies listeners when it changes.
///
/// The session is persisted in [SharedPreferences] so a sign-in survives app
/// restarts. The id token is refreshed lazily: [freshIdToken] hands callers a
/// token that is guaranteed valid for the next call, refreshing transparently
/// when the stored one is near expiry. A failed refresh signs the user out.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';
import 'default_google_authenticator.dart';
import 'firebase_auth_client.dart';
import 'firebase_config.dart';
import 'google_oauth.dart';

class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuthClient? client})
    : _client = client ?? FirebaseAuthClient(config: firebaseConfig);

  static const String _storageKey = 'auth_session';

  final FirebaseAuthClient _client;

  AuthSession? _session;

  AuthSession? get session => _session;
  bool get isSignedIn => _session != null;
  String? get uid => _session?.uid;
  String? get email => _session?.email;
  bool get emailVerified => _session?.emailVerified ?? false;

  /// Profile picture URL for the signed-in user, if the provider supplied one.
  String? get photoUrl => _session?.photoUrl;

  /// Signed in but the email is not yet confirmed: the app gates access behind a
  /// verification screen until this clears.
  bool get needsVerification => isSignedIn && !emailVerified;

  /// Loads any persisted session at startup. Does not eagerly refresh; the first
  /// [freshIdToken] call will refresh if needed.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      _session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    } on FormatException {
      await prefs.remove(_storageKey);
    }
  }

  Future<void> signIn(String email, String password) async {
    final session = await _client.signIn(email.trim(), password);
    await _adopt(await _withVerification(session));
  }

  /// Registers a new account and sends it a verification email. Sign-in still
  /// succeeds immediately (verification is soft); the email just needs
  /// confirming later.
  Future<void> signUp(String email, String password) async {
    final session = await _client.signUp(email.trim(), password);
    await _adopt(session);

    try {
      await _client.sendVerificationEmail(session.idToken);
    } on FirebaseAuthException {
      // Non-fatal: the user can resend from the account menu.
    }
  }

  /// Signs in with Google: runs the OAuth flow to get a Google id token, then
  /// exchanges it for a Firebase session. Google accounts are pre-verified.
  Future<void> signInWithGoogle({GoogleSignInFlow? authenticator}) async {
    final google = authenticator ?? defaultGoogleAuthenticator();
    final idToken = await google.obtainIdToken();
    final session = await _client.signInWithGoogle(
      googleIdToken: idToken,
      requestUri: google.config.redirectUri,
    );

    await _adopt(session);
  }

  /// (Re)sends the verification email for the signed-in user.
  Future<void> sendVerificationEmail() async {
    final token = await freshIdToken();
    if (token != null) {
      await _client.sendVerificationEmail(token);
    }
  }

  /// Sends a password-reset email to [email].
  Future<void> sendPasswordReset(String email) =>
      _client.sendPasswordReset(email.trim());

  /// Re-checks whether the email has been verified and updates the session.
  /// Returns the current verification state.
  Future<bool> reloadEmailVerified() async {
    final token = await freshIdToken();
    if (token == null) {
      return false;
    }

    final verified = await _client.fetchEmailVerified(token);
    final current = _session;
    if (current != null && current.emailVerified != verified) {
      await _adopt(current.copyWith(emailVerified: verified));
    }

    return verified;
  }

  Future<void> signOut() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }

  /// Returns a valid id token for the signed-in user, refreshing it first when
  /// it is near expiry. Returns `null` when signed out or when a refresh fails
  /// (in which case the user is signed out).
  Future<String?> freshIdToken() async {
    final current = _session;

    if (current == null) {
      return null;
    }

    if (!current.needsRefresh) {
      return current.idToken;
    }

    try {
      final refreshed = await _client.refresh(current);
      await _adopt(refreshed);

      return refreshed.idToken;
    } on FirebaseAuthException {
      await signOut();

      return null;
    }
  }

  /// Fills in the verification flag for a freshly signed-in session via a
  /// lookup; falls back to the session unchanged if the lookup fails.
  Future<AuthSession> _withVerification(AuthSession session) async {
    try {
      final verified = await _client.fetchEmailVerified(session.idToken);

      return session.copyWith(emailVerified: verified);
    } on FirebaseAuthException {
      return session;
    }
  }

  Future<void> _adopt(AuthSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(session.toJson()));
    notifyListeners();
  }
}
