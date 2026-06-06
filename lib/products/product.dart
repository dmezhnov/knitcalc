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
///
/// No user-facing text lives here: products name their labels as
/// [LocalizedString] resolvers that look the text up in [AppLocalizations], so
/// the actual strings stay in lib/l10n/*.arb and can be switched at runtime.
library;

import 'package:knitcalc/l10n/app_localizations.dart';

/// Resolves a user-facing string for the active locale. Each product points at
/// the generated [AppLocalizations] getter for its label rather than holding the
/// literal text, keeping translations out of the implementation.
typedef LocalizedString = String Function(AppLocalizations l10n);

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

  /// Resolves the field label for the active locale.
  final LocalizedString label;

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

  /// Resolves the row label for the active locale. May depend on the inputs
  /// (e.g. decreases vs increases), so the product picks the right getter.
  final LocalizedString label;

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

  /// Resolves the product name shown in the dropdown for the active locale.
  LocalizedString get name;

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
