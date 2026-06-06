/// Registry of every product the calculator offers.
///
/// The UI builds its dropdown from [products] and looks products up by id.
/// Register a new product here once its file exists; nothing else needs editing.
library;

import 'product.dart';
import 'rectangular_scarf.dart';
import 'triangular_shawl.dart';

export 'product.dart';

/// All supported products, in dropdown order. The first entry is the default.
const List<Product> products = [RectangularScarf(), TriangularShawl()];

/// The product registered under [id], or the first product as a fallback.
Product productById(String id) => products.firstWhere(
  (product) => product.id == id,
  orElse: () => products.first,
);
