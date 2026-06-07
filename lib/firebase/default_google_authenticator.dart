/// Exposes the production [GoogleSignInFlow] for the current platform, resolved
/// at compile time: the loopback flow on `dart:io` targets (desktop + mobile),
/// the implicit popup flow on the web, and a throwing stub otherwise.
library;

export 'google_authenticator_stub.dart'
    if (dart.library.io) 'google_authenticator_io.dart'
    if (dart.library.js_interop) 'google_authenticator_web.dart';
