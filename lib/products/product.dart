/// Abstractions shared by every product (вид изделия).
///
/// A product is fully described by three things:
///   * which inputs it needs ([inputs]),
///   * which outputs it produces and how they are computed from the inputs
///     ([computeOutputs]),
///   * how it is labelled and identified in the UI ([id], [name]).
///
/// The UI knows nothing about specific products: it renders [inputs] as fields,
/// feeds the entered values back into [computeOutputs], and renders the result.
/// Adding a new product means adding one file — no UI changes required.
library;

/// A single numeric input field of a product.
class ProductInput {
  const ProductInput({
    required this.key,
    required this.label,
    this.allowDecimal = true,
  });

  /// Stable identifier, also used as the widget [Key] and the map key passed to
  /// [Product.computeOutputs].
  final String key;

  /// Russian label shown to the user.
  final String label;

  /// Whether the field accepts a fractional value.
  final bool allowDecimal;
}

/// A single computed result of a product.
class ProductOutput {
  const ProductOutput({
    required this.key,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  /// Stable identifier, also used as the widget [Key].
  final String key;

  /// Russian label shown to the user. May depend on the inputs (e.g. "Убавок"
  /// vs "Прибавок").
  final String label;

  /// The computed number, or `null` when it cannot be computed. Formatting is a
  /// presentation concern handled by the UI.
  final double? value;

  /// When `true` the UI highlights the row to warn the user about [value]
  /// (e.g. a non-integer change rate).
  final bool highlight;
}

/// A kind of knitted item the calculator supports.
abstract class Product {
  const Product();

  /// Stable identifier, used as the dropdown value.
  String get id;

  /// Russian name shown in the product dropdown.
  String get name;

  /// The inputs this product needs, in display order.
  List<ProductInput> get inputs;

  /// Computes the outputs from the entered [values], keyed by [ProductInput.key].
  /// A missing or unparsable field is passed as `null`.
  List<ProductOutput> computeOutputs(Map<String, double?> values);
}

/// Divides preserving the calculator's null semantics: an absent operand or a
/// zero denominator yields `0` rather than `null`/infinity.
double? divide(double? numerator, double? denominator) {
  if (numerator == null || denominator == null || denominator == 0) {
    return 0;
  }

  return numerator / denominator;
}

/// Multiplies preserving the calculator's null semantics: an absent operand
/// yields `0`.
double? multiply(double? multiplicand, double? multiplier) {
  if (multiplicand == null || multiplier == null) {
    return 0.0;
  }

  return multiplicand * multiplier;
}
