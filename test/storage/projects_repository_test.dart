import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/storage/projects_repository.dart';
import 'package:knitcalc/storage/saved_project.dart';

void main() {
  const repository = ProjectsRepository();

  setUp(() {
    // Each test starts with an empty store; the mock backs getInstance().
    SharedPreferences.setMockInitialValues({});
  });

  SavedProject sample({
    required String id,
    String name = 'Scarf',
    String description = '',
    List<String> photos = const [],
    int coverIndex = 0,
    DateTime? updatedAt,
  }) {
    return SavedProject(
      id: id,
      name: name,
      productId: 'rectangular_scarf',
      values: const {'stitches': '15', 'sampleWidthCm': '10,5'},
      description: description,
      photos: photos,
      coverIndex: coverIndex,
      updatedAt: updatedAt ?? DateTime(2026, 6, 7),
    );
  }

  test('loadAll is empty initially', () async {
    expect(await repository.loadAll(), isEmpty);
  });

  test('upsert then loadAll returns the project', () async {
    await repository.upsert(sample(id: '1'));

    final all = await repository.loadAll();

    expect(all, hasLength(1));
    expect(all.single.name, 'Scarf');
    expect(all.single.values['sampleWidthCm'], '10,5');
  });

  test('upsert with an existing id updates in place, no duplicate', () async {
    await repository.upsert(sample(id: '1', name: 'Old'));
    await repository.upsert(sample(id: '1', name: 'New'));

    final all = await repository.loadAll();

    expect(all, hasLength(1));
    expect(all.single.name, 'New');
  });

  test('loadAll is sorted newest-first by updatedAt', () async {
    await repository.upsert(
      sample(id: 'old', name: 'Old', updatedAt: DateTime(2026, 1, 1)),
    );
    await repository.upsert(
      sample(id: 'new', name: 'New', updatedAt: DateTime(2026, 12, 1)),
    );

    final all = await repository.loadAll();

    expect(all.map((p) => p.name), ['New', 'Old']);
  });

  test('delete removes the project', () async {
    await repository.upsert(sample(id: '1'));
    await repository.delete('1');

    expect(await repository.loadAll(), isEmpty);
  });

  test('toJson/fromJson round-trips every field', () {
    final project = sample(
      id: '1',
      description: 'soft merino',
      photos: const ['photoA', 'photoB'],
      coverIndex: 1,
      updatedAt: DateTime(2026, 6, 7, 8, 9, 10),
    );

    final restored = SavedProject.fromJson(project.toJson());

    expect(restored.id, project.id);
    expect(restored.name, project.name);
    expect(restored.productId, project.productId);
    expect(restored.values, project.values);
    expect(restored.description, project.description);
    expect(restored.photos, project.photos);
    expect(restored.coverIndex, project.coverIndex);
    expect(restored.updatedAt, project.updatedAt);
  });

  test(
    'fromJson defaults description and photos when absent (old records)',
    () {
      final json = sample(id: '1').toJson()
        ..remove('description')
        ..remove('photos')
        ..remove('coverIndex');

      final restored = SavedProject.fromJson(json);

      expect(restored.description, '');
      expect(restored.photos, isEmpty);
      expect(restored.coverIndex, 0);
    },
  );
}
