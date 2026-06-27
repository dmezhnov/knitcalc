import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/firebase/session_store_io.dart';

void main() {
  late Directory tmp;

  /// A FileSessionStore writing into a throwaway temp dir, so the test needs no
  /// path_provider platform mock.
  FileSessionStore storeIn(Directory dir) =>
      FileSessionStore(supportDir: () async => dir);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('session_store_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test('writes, reads and clears the session file', () async {
    final store = storeIn(tmp);
    final file = File('${tmp.path}/auth_session.json');

    expect(await store.read(), isNull);

    await store.write('{"uid":"u"}');
    expect(file.existsSync(), isTrue);
    expect(await store.read(), '{"uid":"u"}');

    await store.clear();
    expect(await store.read(), isNull);
    expect(file.existsSync(), isFalse);
  });

  test(
    'migrates a legacy SharedPreferences session, then drops the old key',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_session': '{"uid":"legacy"}',
      });

      final store = storeIn(tmp);

      // First read pulls the session out of the old pref into the file...
      expect(await store.read(), '{"uid":"legacy"}');
      expect(File('${tmp.path}/auth_session.json').existsSync(), isTrue);

      // ...and removes the legacy pref so it can't resurrect a stale session.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_session'), isNull);
    },
  );

  test('clear also removes a lingering legacy pref', () async {
    SharedPreferences.setMockInitialValues({
      'auth_session': '{"uid":"legacy"}',
    });

    await storeIn(tmp).clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_session'), isNull);
  });
}
