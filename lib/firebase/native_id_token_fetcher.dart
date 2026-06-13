/// Production [NativeIdTokenFetcher]: the only file that imports
/// `package:google_sign_in`, so it is the single swap point for the F-Droid
/// `foss` build, which replaces it with `native_id_token_fetcher_foss.dart`
/// (no Play Services) and drops the dependency from `pubspec.yaml`. See
/// `packaging/README.md`.
///
/// `google_authenticator_io.dart` injects [defaultNativeIdTokenFetcher] into
/// [NativeFirstGoogleSignInFlow]; tests inject a fake instead, so this SDK call
/// is never exercised off-device.
library;

import 'package:google_sign_in/google_sign_in.dart';

import 'google_oauth.dart';
import 'native_google_sign_in.dart';

// initialize() must run once per process; memoise it so a re-created flow (one
// per sign-in attempt) doesn't re-initialise the singleton.
Future<void>? _initialization;

/// Runs the native Android account picker (Credential Manager) for
/// [serverClientId] and returns a Google `id_token`. Throws
/// [GoogleAuthCancelledException] when the user dismisses the picker and
/// [NativeSignInUnavailable] when it cannot run at all.
Future<String> defaultNativeIdTokenFetcher(String serverClientId) async {
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
