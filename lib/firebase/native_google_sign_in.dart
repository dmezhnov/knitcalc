/// Android native account picker (Credential Manager) for Google sign-in:
/// tries the on-device picker first and falls back to the loopback browser
/// flow when it can't run.
///
/// Only ever used on Android (see `google_authenticator_io.dart`, gated behind
/// `Platform.isAndroid`): web's `authenticate()` is unsupported and iOS/macOS
/// keep the loopback browser flow. The native call sits behind the injectable
/// [NativeIdTokenFetcher] seam so the fallback/cancel logic stays unit-testable
/// without an emulator — the picker itself is on-device only.
///
/// The seam also keeps the only `package:google_sign_in` import in a single
/// swappable leaf (`native_id_token_fetcher.dart`): the F-Droid `foss` build
/// replaces it with `native_id_token_fetcher_foss.dart`, which drops the
/// proprietary Play Services dependency and always falls back to the browser.
/// See `packaging/README.md`.
library;

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

/// A [GoogleSignInFlow] that tries the native Android account picker first and
/// falls back to [_fallback] (the loopback browser flow) when it is
/// unavailable. A native cancel is propagated as-is rather than falling back.
///
/// [fetchNative] is injected by the composition root
/// (`google_authenticator_io.dart` passes `defaultNativeIdTokenFetcher`); tests
/// pass a fake. This file imports no platform SDK so it compiles in the `foss`
/// build, where the injected fetcher is the no-op stub.
class NativeFirstGoogleSignInFlow implements GoogleSignInFlow {
  NativeFirstGoogleSignInFlow({
    required this.serverClientId,
    required GoogleSignInFlow fallback,
    required NativeIdTokenFetcher fetchNative,
  }) : _fallback = fallback,
       _fetchNative = fetchNative;

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
