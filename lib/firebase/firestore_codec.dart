/// Pure conversion between [SavedProject] and the Firestore REST document shape.
///
/// Firestore's REST API represents every value as a tagged union, e.g.
/// `{"stringValue": "x"}`, `{"booleanValue": true}`, maps as
/// `{"mapValue": {"fields": {...}}}` and lists as `{"arrayValue": {"values":
/// [...]}}`. These helpers translate a project to that form and back. The
/// project [SavedProject.id] is not stored as a field — it is the document id
/// (the last path segment of the document `name`).
library;

import '../storage/saved_project.dart';

/// Builds the request body for a Firestore `patch` (create/update) call.
Map<String, dynamic> encodeProjectFields(SavedProject project) {
  return {
    'fields': {
      'name': {'stringValue': project.name},
      'productId': {'stringValue': project.productId},
      'description': {'stringValue': project.description},
      'deleted': {'booleanValue': project.deleted},
      'updatedAt': {
        'timestampValue': project.updatedAt.toUtc().toIso8601String(),
      },
      'values': {
        'mapValue': {
          'fields': {
            for (final entry in project.values.entries)
              entry.key: {'stringValue': entry.value},
          },
        },
      },
      'photos': {
        'arrayValue': {
          'values': [
            for (final photo in project.photos) {'stringValue': photo},
          ],
        },
      },
    },
  };
}

/// Rebuilds a [SavedProject] from a Firestore document (`{name, fields, ...}`).
SavedProject decodeProjectDocument(Map<String, dynamic> document) {
  final name = document['name'] as String;
  final id = name.split('/').last;
  final fields = (document['fields'] as Map<String, dynamic>? ?? const {});

  String str(String key) => fields[key]?['stringValue'] as String? ?? '';

  final rawValues =
      (fields['values']?['mapValue']?['fields'] as Map<String, dynamic>? ??
      const {});
  final rawPhotos =
      (fields['photos']?['arrayValue']?['values'] as List<dynamic>? ??
      const []);

  return SavedProject(
    id: id,
    name: str('name'),
    productId: str('productId'),
    description: str('description'),
    deleted: fields['deleted']?['booleanValue'] as bool? ?? false,
    values: {
      for (final entry in rawValues.entries)
        entry.key: entry.value['stringValue'] as String,
    },
    photos: [for (final value in rawPhotos) value['stringValue'] as String],
    updatedAt: DateTime.parse(fields['updatedAt']?['timestampValue'] as String),
  );
}
