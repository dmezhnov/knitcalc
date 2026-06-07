/// Renders the signed-in user's profile picture, picking the per-platform
/// implementation at compile time (web needs a real `<img>` element; see
/// `account_avatar_web.dart`).
library;

export 'account_avatar_stub.dart'
    if (dart.library.io) 'account_avatar_io.dart'
    if (dart.library.js_interop) 'account_avatar_web.dart';
