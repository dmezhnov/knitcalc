/// A user-saved calculation: a named snapshot of one product's input fields.
///
/// It captures only what the user is responsible for — which product was chosen
/// and the raw text typed into each field — so loading it restores the screen
/// exactly. Outputs are derived on load via [Product.computeOutputs] and are not
/// stored. Values are kept as the raw strings the user typed (e.g. "12,5" with a
/// comma) rather than parsed numbers, so a reloaded field looks identical to
/// what was entered.
library;

class SavedProject {
  const SavedProject({
    required this.id,
    required this.name,
    required this.productId,
    required this.values,
    required this.updatedAt,
    this.description = '',
    this.photos = const [],
  });

  /// Mints a new project with a unique [id] derived from the current time.
  factory SavedProject.create({
    required String name,
    required String productId,
    required Map<String, String> values,
    String description = '',
    List<String> photos = const [],
    DateTime? updatedAt,
  }) {
    final now = updatedAt ?? DateTime.now();

    return SavedProject(
      id: now.microsecondsSinceEpoch.toString(),
      name: name,
      productId: productId,
      values: values,
      description: description,
      photos: photos,
      updatedAt: now,
    );
  }

  factory SavedProject.fromJson(Map<String, dynamic> json) {
    final rawValues = (json['values'] as Map<String, dynamic>? ?? const {});
    final rawPhotos = (json['photos'] as List<dynamic>? ?? const []);

    return SavedProject(
      id: json['id'] as String,
      name: json['name'] as String,
      productId: json['productId'] as String,
      values: {
        for (final entry in rawValues.entries) entry.key: entry.value as String,
      },
      description: json['description'] as String? ?? '',
      photos: [for (final photo in rawPhotos) photo as String],
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Stable unique identifier, also the key used to upsert/delete in storage.
  final String id;

  /// User-given display name shown in the saved-projects list.
  final String name;

  /// Which [Product] this snapshot belongs to (see [productById]).
  final String productId;

  /// Raw field text keyed by [ProductInput.key].
  final Map<String, String> values;

  /// Free-text note the user attached to the project.
  final String description;

  /// Attached photos, each a base64-encoded JPEG (see photo_codec.dart).
  final List<String> photos;

  /// When the project was last created or modified; drives list ordering.
  final DateTime updatedAt;

  SavedProject copyWith({
    String? name,
    String? productId,
    Map<String, String>? values,
    String? description,
    List<String>? photos,
    DateTime? updatedAt,
  }) {
    return SavedProject(
      id: id,
      name: name ?? this.name,
      productId: productId ?? this.productId,
      values: values ?? this.values,
      description: description ?? this.description,
      photos: photos ?? this.photos,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'productId': productId,
    'values': values,
    'description': description,
    'photos': photos,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
