import 'gauge.dart';
import 'product.dart';

/// Скос плеча — the sloped edge of a shoulder, knitted by decreasing the
/// shoulder's stitches away over its height.
///
/// The decreases are worked in every other row, so a slope that is N rows high
/// gets N / 2 decrease rows; the shoulder's stitches are then spread over those
/// rows as evenly as they divide. They rarely divide exactly, which leaves two
/// group sizes one stitch apart — 32 stitches over 7 rows means four rows of 5
/// plus three rows of 4.
class ShoulderSlope extends Product {
  const ShoulderSlope();

  @override
  String get id => 'shoulder_slope';

  @override
  LocalizedString get name =>
      (l10n) => l10n.productShoulderSlope;

  @override
  List<ProductInput> get inputs => [
    ...gaugeInputs,
    ProductInput(key: 'shoulderWidthCm', label: (l10n) => l10n.shoulderWidthCm),
    ProductInput(
      key: 'shoulderHeightCm',
      label: (l10n) => l10n.shoulderHeightCm,
      hint: (l10n) => l10n.shoulderHeightHint,
    ),
  ];

  @override
  List<ProductOutput> computeOutputs(Map<String, double?> values) {
    final widthStitches = multiply(
      gaugeStitchesPerCm(values),
      values['shoulderWidthCm'],
    )?.roundToDouble();
    final heightRows = multiply(
      gaugeRowsPerCm(values),
      values['shoulderHeightCm'],
    )?.roundToDouble();

    // Every other row carries a decrease, so half the rows do; a slope one row
    // high still gets the single decrease row that rounding gives it.
    final decreaseRows = heightRows == null || heightRows <= 0
        ? null
        : (heightRows / 2).round();

    final stitches = widthStitches?.toInt() ?? 0;
    final canSplit = decreaseRows != null && decreaseRows > 0 && stitches > 0;

    // The remainder of the division is the number of rows that take one stitch
    // more than the rest; the two groups together always use up every stitch.
    final smallStep = canSplit ? stitches ~/ decreaseRows : 0;
    final largeStepRows = canSplit ? stitches % decreaseRows : 0;
    final smallStepRows = canSplit ? decreaseRows - largeStepRows : 0;

    return [
      ...gaugeOutputs(values),
      ProductOutput(
        key: 'shoulderWidthStitches',
        label: (l10n) => l10n.shoulderWidthStitches,
        value: widthStitches,
      ),
      ProductOutput(
        key: 'shoulderHeightRows',
        label: (l10n) => l10n.shoulderHeightRows,
        value: heightRows,
      ),
      ProductOutput(
        key: 'decreaseRows',
        label: (l10n) => l10n.shoulderDecreaseRows,
        value: decreaseRows?.toDouble(),
      ),
      // Each group is listed only while it has rows in it: an exact division
      // leaves no larger group, and a shoulder narrower than it is tall leaves
      // rows with nothing to decrease.
      if (largeStepRows > 0)
        ProductOutput(
          key: 'largeStepRows',
          label: (l10n) => l10n.shoulderStepRows(smallStep + 1),
          value: largeStepRows.toDouble(),
        ),
      if (smallStep > 0 && smallStepRows > 0)
        ProductOutput(
          key: 'smallStepRows',
          label: (l10n) => l10n.shoulderStepRows(smallStep),
          value: smallStepRows.toDouble(),
        ),
    ];
  }
}
