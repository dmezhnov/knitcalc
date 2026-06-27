/// Persists the serialized [AuthSession] JSON, kept apart from the rest of the
/// app's preferences so the Windows uninstaller can sign the user out (by
/// deleting just this) without touching their saved projects (which live in
/// shared_preferences). See packaging/inno/knitcalc.iss.
///
/// On dart:io platforms the session lives in its own `auth_session.json` file in
/// the app-support directory; on web it stays in SharedPreferences (there is no
/// uninstaller and no file system). [defaultSessionStore] picks the right one per
/// platform; tests inject [PrefsSessionStore] directly.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'session_store_io.dart'
    if (dart.library.html) 'session_store_web.dart'
    as platform;

/// Storage key — also the legacy SharedPreferences key the file store migrates
/// from on dart:io.
const String sessionStorageKey = 'auth_session';

/// Reads/writes/clears the persisted session JSON.
abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// The platform default: a file-backed store on desktop/mobile, prefs on web.
SessionStore defaultSessionStore() => platform.createSessionStore();

/// SharedPreferences-backed store. Used on web, and as a simple injectable store
/// in tests; the desktop/mobile default is the file-backed store instead.
class PrefsSessionStore implements SessionStore {
  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(sessionStorageKey);
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  @override
  Future<void> write(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sessionStorageKey, value);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(sessionStorageKey);
  }
}
