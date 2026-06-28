import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:knitcalc/storage/data_dir_migration_io.dart';

void main() {
  late Directory from;
  late Directory to;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('data_dir_migration');
    from = Directory('${root.path}/from');
    to = Directory('${root.path}/to');
  });

  tearDown(() async {
    if (from.parent.existsSync()) {
      await from.parent.delete(recursive: true);
    }
  });

  test('copies every file to the new dir and removes the old one', () async {
    await from.create(recursive: true);
    await File('${from.path}/shared_preferences.json').writeAsString('{"a":1}');
    await File('${from.path}/auth_session.json').writeAsString('{"uid":"u"}');

    await migrateDataDir(from: from, to: to);

    expect(from.existsSync(), isFalse);
    expect(
      await File('${to.path}/shared_preferences.json').readAsString(),
      '{"a":1}',
    );
    expect(
      await File('${to.path}/auth_session.json').readAsString(),
      '{"uid":"u"}',
    );
  });

  test(
    'is a no-op when the new dir already holds the projects store',
    () async {
      await from.create(recursive: true);
      await File(
        '${from.path}/shared_preferences.json',
      ).writeAsString('{"old":1}');
      await to.create(recursive: true);
      await File(
        '${to.path}/shared_preferences.json',
      ).writeAsString('{"new":1}');

      await migrateDataDir(from: from, to: to);

      // New data is preserved and the old dir is left untouched (not migrated).
      expect(
        await File('${to.path}/shared_preferences.json').readAsString(),
        '{"new":1}',
      );
      expect(from.existsSync(), isTrue);
    },
  );

  test('is a no-op when the old dir is absent', () async {
    await migrateDataDir(from: from, to: to);

    expect(from.existsSync(), isFalse);
    expect(to.existsSync(), isFalse);
  });
}
