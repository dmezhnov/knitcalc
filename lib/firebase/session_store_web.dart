import 'session_store.dart';

/// On web there is no uninstaller and no file system, so the session stays in
/// SharedPreferences (localStorage). See [defaultSessionStore].
SessionStore createSessionStore() => PrefsSessionStore();
