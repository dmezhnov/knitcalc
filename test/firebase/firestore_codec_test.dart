import 'package:flutter_test/flutter_test.dart';

import 'package:knitcalc/firebase/firestore_codec.dart';
import 'package:knitcalc/storage/saved_project.dart';

void main() {
  /// Wraps encoded fields as a Firestore document the way a read would return
  /// it, so encode/decode can be round-tripped without the network.
  Map<String, dynamic> asDocument(String uid, SavedProject project) {
    final encoded = encodeProjectFields(project);
    return {
      'name':
          'projects/p/databases/(default)/documents/users/$uid/projects/${project.id}',
      'fields': encoded['fields'],
    };
  }

  test('encode/decode round-trips every field', () {
    final project = SavedProject(
      id: '1700000000000000',
      name: 'Шарф',
      productId: 'rectangular_scarf',
      values: const {'stitches': '15', 'sampleWidthCm': '10,5'},
      description: 'soft merino',
      photos: const ['photoA', 'photoB'],
      coverIndex: 1,
      deleted: false,
      updatedAt: DateTime.utc(2026, 6, 7, 8, 9, 10),
    );

    final restored = decodeProjectDocument(asDocument('uid1', project));

    expect(restored.id, project.id);
    expect(restored.name, project.name);
    expect(restored.productId, project.productId);
    expect(restored.values, project.values);
    expect(restored.description, project.description);
    expect(restored.photos, project.photos);
    expect(restored.coverIndex, project.coverIndex);
    expect(restored.deleted, isFalse);
    expect(restored.updatedAt.isAtSameMomentAs(project.updatedAt), isTrue);
  });

  test('decodes a tombstone and empty collections', () {
    final tombstone = SavedProject(
      id: '2',
      name: 'gone',
      productId: 'rectangular_scarf',
      values: const {},
      photos: const [],
      deleted: true,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final restored = decodeProjectDocument(asDocument('uid1', tombstone));

    expect(restored.deleted, isTrue);
    expect(restored.values, isEmpty);
    expect(restored.photos, isEmpty);
  });

  test('decode tolerates an arrayValue with no values key', () {
    // Firestore omits "values" for an empty array on read.
    final document = {
      'name': 'a/b/c/documents/users/u/projects/3',
      'fields': {
        'name': {'stringValue': 'x'},
        'productId': {'stringValue': 'p'},
        'description': {'stringValue': ''},
        'updatedAt': {'timestampValue': '2026-01-01T00:00:00Z'},
        'values': {'mapValue': <String, dynamic>{}},
        'photos': {'arrayValue': <String, dynamic>{}},
      },
    };

    final restored = decodeProjectDocument(document);

    expect(restored.photos, isEmpty);
    expect(restored.values, isEmpty);
    expect(restored.deleted, isFalse);
    // Records predating coverIndex decode to the first-photo default.
    expect(restored.coverIndex, 0);
  });
}
