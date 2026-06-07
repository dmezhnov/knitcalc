/// Fallback used when neither `dart:io` nor `dart:js_interop` is available.
/// Selecting a Google flow here is unreachable in practice; it throws clearly.
library;

import 'google_oauth.dart';

GoogleSignInFlow defaultGoogleAuthenticator() =>
    throw const GoogleAuthException(
      'Google sign-in is unsupported on this platform',
    );
