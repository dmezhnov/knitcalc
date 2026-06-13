/// FOSS [NativeIdTokenFetcher]: the F-Droid `foss` build copies this over
/// `native_id_token_fetcher.dart` so the APK carries no `package:google_sign_in`
/// (and therefore no proprietary Play Services), which F-Droid's source build
/// and scanner require. See `packaging/README.md`.
///
/// With the native picker stripped, [defaultNativeIdTokenFetcher] always signals
/// [NativeSignInUnavailable], so [NativeFirstGoogleSignInFlow] falls straight
/// through to the loopback browser OAuth flow — the same path Play-Services-less
/// devices already take. This file imports no platform SDK.
library;

import 'native_google_sign_in.dart';

/// Always unavailable: the FOSS build has no native account picker, so sign-in
/// uses the loopback browser flow.
Future<String> defaultNativeIdTokenFetcher(String serverClientId) async {
  throw const NativeSignInUnavailable(
    'foss build: native Google sign-in stripped',
  );
}
