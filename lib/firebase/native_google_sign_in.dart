/// Android native account picker (Credential Manager) for Google sign-in,
/// wrapping `package:google_sign_in` 7.x and returning a Google `id_token`.
///
/// Only ever used on Android (see `google_authenticator_io.dart`, gated behind
/// `Platform.isAndroid`): web's `authenticate()` is unsupported and iOS/macOS
/// keep the loopback browser flow. The native call sits behind the injectable
/// [NativeIdTokenFetcher] seam so the fallback/cancel logic stays unit-testable
/// without an emulator — the picker itself is on-device only.
library;

import 'package:google_sign_in/google_sign_in.dart';

import 'google_oauth.dart';

/// Thrown by a [NativeIdTokenFetcher] when the native picker cannot run — no
/// Google Play Services, an unregistered signing key, no on-device credential,
/// or a provider misconfiguration. Distinct from [GoogleAuthCancelledException]
/// (a deliberate dismissal) so the wrapper can fall back only on the former.
class NativeSignInUnavailable implements Exception {
  const NativeSignInUnavailable(this.message);

  final String message;

  @override
  String toString() => 'NativeSignInUnavailable($message)';
}

/// Runs the native picker for [serverClientId] and returns a Google `id_token`.
/// Throws [GoogleAuthCancelledException] when the user dismisses the picker and
/// [NativeSignInUnavailable] when it cannot run at all.
typedef NativeIdTokenFetcher = Future<String> Function(String serverClientId);

// initialize() must run once per process; memoise it so a re-created flow (one
// per sign-in attempt) doesn't re-initialise the singleton.
Future<void>? _initialization;

Future<String> _defaultNativeIdTokenFetcher(String serverClientId) async {
  final signIn = GoogleSignIn.instance;
  try {
    _initialization ??= signIn.initialize(serverClientId: serverClientId);
    await _initialization;

    // False only on web, which never reaches this dart:io path; guard anyway so
    // an unexpected platform falls back cleanly rather than throwing.
    if (!signIn.supportsAuthenticate()) {
      throw const NativeSignInUnavailable('authenticate unsupported');
    }

    final account = await signIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const NativeSignInUnavailable(
        'no id_token from Credential Manager',
      );
    }

    return idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      throw const GoogleAuthCancelledException();
    }
    // Anything that isn't a deliberate cancel (no Play Services, unregistered
    // SHA-1, no on-device credential, misconfig) becomes a fall-back signal.
    throw NativeSignInUnavailable('${e.code}: ${e.description}');
  }
}

/// A [GoogleSignInFlow] that tries the native Android account picker first and
/// falls back to [_fallback] (the loopback browser flow) when it is
/// unavailable. A native cancel is propagated as-is rather than falling back.
class NativeFirstGoogleSignInFlow implements GoogleSignInFlow {
  NativeFirstGoogleSignInFlow({
    required this.serverClientId,
    required GoogleSignInFlow fallback,
    NativeIdTokenFetcher? fetchNative,
  }) : _fallback = fallback,
       _fetchNative = fetchNative ?? _defaultNativeIdTokenFetcher;

  final String serverClientId;
  final GoogleSignInFlow _fallback;
  final NativeIdTokenFetcher _fetchNative;

  bool _usingFallback = false;

  // Reuse the fallback's loopback config so the id token still ships with a
  // consistent requestUri to signInWithIdp.
  @override
  GoogleOAuthConfig get config => _fallback.config;

  @override
  Future<String> obtainIdToken() async {
    try {
      return await _fetchNative(serverClientId);
    } on GoogleAuthCancelledException {
      // The user dismissed the native picker — a cancel, not a failure.
      rethrow;
    } on NativeSignInUnavailable {
      _usingFallback = true;
      return _fallback.obtainIdToken();
    }
  }

  @override
  void cancel() {
    // Only the browser fallback exposes an abortable wait; the native picker
    // handles its own dismissal (surfaced as a cancel above). Forward only once
    // the fallback is engaged, so we don't pre-complete its cancel signal.
    if (_usingFallback) {
      _fallback.cancel();
    }
  }
}
