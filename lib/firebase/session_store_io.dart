import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_store.dart';

/// Resolves the directory the session file lives in. Injectable for tests so
/// they need no path_provider platform mock; defaults to the app-support dir.
typedef SupportDirResolver = Future<Directory> Function();

/// dart:io default — see [defaultSessionStore].
SessionStore createSessionStore() => FileSessionStore();

/// Keeps the session in its own `auth_session.json` in the app-support directory
/// (on Windows: `%APPDATA%\<company>\<product>`, the same folder as
/// shared_preferences). Holding it in a separate file lets the uninstaller sign
/// the user out by deleting just this file, leaving saved projects intact (see
/// packaging/inno/knitcalc.iss).
class FileSessionStore implements SessionStore {
  FileSessionStore({SupportDirResolver? supportDir})
    : _supportDir = supportDir ?? getApplicationSupportDirectory;

  static const String _fileName = 'auth_session.json';

  final SupportDirResolver _supportDir;

  Future<File> _file() async {
    final dir = await _supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  @override
  Future<String?> read() async {
    final file = await _file();

    if (file.existsSync()) {
      final raw = await file.readAsString();
      return raw.isEmpty ? null : raw;
    }

    // Migrate a session written by the previous SharedPreferences-backed store
    // so an already-signed-in user stays signed in across this update.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(sessionStorageKey);

    if (legacy != null && legacy.isNotEmpty) {
      await file.writeAsString(legacy);
      await prefs.remove(sessionStorageKey);
      return legacy;
    }

    return null;
  }

  @override
  Future<void> write(String value) async {
    final file = await _file();
    await file.writeAsString(value);
  }

  @override
  Future<void> clear() async {
    final file = await _file();

    if (file.existsSync()) {
      await file.delete();
    }

    // Drop any lingering legacy pref so a stale one can't resurrect the session.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(sessionStorageKey);
  }
}
