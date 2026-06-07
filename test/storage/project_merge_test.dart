import 'package:flutter_test/flutter_test.dart';

import 'package:knitcalc/storage/project_merge.dart';
import 'package:knitcalc/storage/saved_project.dart';

void main() {
  SavedProject at(String id, DateTime updatedAt, {bool deleted = false}) {
    return SavedProject(
      id: id,
      name: id,
      productId: 'rectangular_scarf',
      values: const {},
      deleted: deleted,
      updatedAt: updatedAt,
    );
  }

  test('remote-only records are adopted, not re-uploaded', () {
    final result = mergeForSync([], [at('r', DateTime(2026, 1, 1))]);

    expect(result.merged.map((p) => p.id), ['r']);
    expect(result.toUpload, isEmpty);
  });

  test('local-only records are kept and queued for upload', () {
    final result = mergeForSync([at('l', DateTime(2026, 1, 1))], []);

    expect(result.merged.map((p) => p.id), ['l']);
    expect(result.toUpload.map((p) => p.id), ['l']);
  });

  test('newer local wins and is uploaded', () {
    final result = mergeForSync(
      [at('x', DateTime(2026, 6, 1))],
      [at('x', DateTime(2026, 1, 1))],
    );

    expect(result.merged.single.updatedAt, DateTime(2026, 6, 1));
    expect(result.toUpload.map((p) => p.id), ['x']);
  });

  test('newer remote wins and is not uploaded', () {
    final result = mergeForSync(
      [at('x', DateTime(2026, 1, 1))],
      [at('x', DateTime(2026, 6, 1))],
    );

    expect(result.merged.single.updatedAt, DateTime(2026, 6, 1));
    expect(result.toUpload, isEmpty);
  });

  test('ties resolve to remote', () {
    final ts = DateTime(2026, 3, 3);
    final result = mergeForSync(
      [at('x', ts, deleted: false)],
      [at('x', ts, deleted: true)],
    );

    expect(result.merged.single.deleted, isTrue, reason: 'remote copy kept');
    expect(result.toUpload, isEmpty);
  });

  test('a newer remote tombstone wins over an older local record', () {
    final result = mergeForSync(
      [at('x', DateTime(2026, 1, 1), deleted: false)],
      [at('x', DateTime(2026, 6, 1), deleted: true)],
    );

    expect(result.merged.single.deleted, isTrue);
  });
}
