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

  /// The Google flow currently running, so [cancelGoogleSignIn] can abort it.
  GoogleSignInFlow? _googleFlow;

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
    _googleFlow = google;
    try {
      final idToken = await google.obtainIdToken();
      final session = await _client.signInWithGoogle(
        googleIdToken: idToken,
        requestUri: google.config.redirectUri,
      );

      await _adopt(session);
    } finally {
      _googleFlow = null;
    }
  }

  /// Aborts an in-flight [signInWithGoogle] (e.g. the user closed the consent
  /// browser); the pending call then throws [GoogleAuthCancelledException].
  void cancelGoogleSignIn() => _googleFlow?.cancel();

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

  /// Re-fetches the profile from the backend and, for Google accounts, updates
  /// the cached avatar when it changed (also refreshing the verification flag).
  /// A no-op when signed out or when the lookup fails. Notifies listeners only
  /// when something actually changed, so the avatar repaints in place.
  ///
  /// Caveat: `accounts:lookup` returns Firebase's stored profile, which it only
  /// refreshes from Google at federated sign-in (`signInWithIdp`) — it does not
  /// poll Google. So a Google avatar changed after sign-in is picked up only on
  /// the next Google sign-in (or via another device that re-signed in). This
  /// catches server-side changes Firebase already knows about, not brand-new
  /// ones.
  // TODO: To reflect a freshly changed Google avatar without a re-login, query
  // Google directly (oauth2/v3/userinfo or People API) for its `picture` and
  // adopt that. Requires keeping a Google access/refresh token: request offline
  // access + the `profile` scope during sign-in, persist the refresh token in
  // AuthSession, exchange it for a short-lived access token here, then call
  // userinfo. Weigh the extra secret on-device and OAuth complexity against the
  // benefit before doing this.
  Future<void> refreshProfile() async {
    // Best-effort avatar/verification refresh: it must NEVER throw. A blocked or
    // offline network makes the token refresh or lookup fail with anything from
    // a FirebaseAuthException to a raw timeout/socket/parse error; letting that
    // escape would abort the caller (sync + update check) before it can show its
    // own offline banner. So swallow every failure and just skip the refresh.
    try {
      final token = await freshIdToken();
      final current = _session;
      if (token == null || current == null) {
        return;
      }

      final info = await _client.lookupAccount(token);

      // Only Google supplies an avatar; don't touch a password account's (null).
      final photoUrl = info.isGoogle ? info.photoUrl : current.photoUrl;

      if (current.emailVerified != info.emailVerified ||
          current.photoUrl != photoUrl) {
        await _adopt(
          current.copyWith(
            emailVerified: info.emailVerified,
            photoUrl: photoUrl,
          ),
        );
      }
    } on Object {
      // Ignored on purpose (see above).
    }
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
    } on Object {
      // Best-effort: any failure (FirebaseAuthException or a raw network/parse
      // error on a blocked/offline network) falls back to the session unchanged
      // rather than aborting sign-in.
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
