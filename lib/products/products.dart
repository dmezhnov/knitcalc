/// Registry of every product the calculator offers.
///
/// The products are JSON files under assets/products/; [loadProducts] reads
/// them once at startup, in the order assets/products/index.json lists them.
/// The UI builds its dropdown from [products] and looks products up by id.
/// Add a new product by adding its file and its id to the index; nothing else
/// needs editing.
library;

import 'dart:convert';

import 'product.dart';

export 'product.dart';

/// Where the product files live, relative to the asset bundle root (and to
/// the project root, which is how tests read them).
const String productsDirectory = 'assets/products';

/// Reads a text asset by its path, e.g. `rootBundle.loadString`.
typedef AssetReader = Future<String> Function(String path);

late List<Product> _products;

/// All supported products, in dropdown order. The first entry is the default.
/// Available once [loadProducts] has completed.
List<Product> get products => _products;

/// Reads the index, every product it lists and the shared parts those
/// products include, and makes them [products]. Throws a [FormatException]
/// when a file is malformed, so a broken product fails the tests instead of
/// reaching a user.
Future<void> loadProducts(AssetReader read) async {
  _products = await readProductCatalog(read);
}

/// The products [loadProducts] would install, without installing them.
Future<List<Product>> readProductCatalog(AssetReader read) async {
  final index = jsonDecode(await read('$productsDirectory/index.json'));
  if (index is! Map<String, Object?> || index['products'] is! List<Object?>) {
    throw const FormatException(
      'Product index: expected {"products": ["<id>", ...]}',
    );
  }
  final ids = <String>[];
  for (final id in index['products']! as List<Object?>) {
    if (id is! String || ids.contains(id)) {
      throw FormatException('Product index: bad or repeated id $id');
    }
    ids.add(id);
  }
  if (ids.isEmpty) {
    throw const FormatException('Product index: lists no products');
  }

  final parts = <String, Object?>{};
  final catalog = <Product>[];
  for (final id in ids) {
    final json = jsonDecode(await read('$productsDirectory/$id.json'));
    final include = json is Map<String, Object?> ? json['include'] : null;
    if (include is List<Object?>) {
      for (final part in include.whereType<String>()) {
        parts[part] ??= jsonDecode(
          await read('$productsDirectory/parts/$part.json'),
        );
      }
    }
    catalog.add(Product.fromJson(id, json, parts: parts));
  }

  return catalog;
}

/// The product registered under [id], or the first product as a fallback.
Product productById(String id) => products.firstWhere(
  (product) => product.id == id,
  orElse: () => products.first,
);
