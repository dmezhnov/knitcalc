import 'gauge.dart';
import 'product.dart';

/// Треугольный палантин — a wrap whose width changes linearly from start to end
/// over a target length.
///
/// From the start/end widths we get the stitch counts at each edge; their
/// difference must be spread evenly over the rows as decreases (when narrowing)
/// or increases (when widening), one on each side per change.
class TriangularShawl extends Product {
  const TriangularShawl();

  @override
  String get id => 'triangular_shawl';

  @override
  LocalizedString get name =>
      (l10n) => l10n.productTriangularShawl;

  @override
  List<ProductInput> get inputs => [
    ...gaugeInputs,
    ProductInput(key: 'startWidthCm', label: (l10n) => l10n.shawlStartWidthCm),
    ProductInput(key: 'endWidthCm', label: (l10n) => l10n.shawlEndWidthCm),
    ProductInput(key: 'targetLengthCm', label: (l10n) => l10n.targetLengthCm),
  ];

  @override
  List<ProductOutput> computeOutputs(Map<String, double?> values) {
    final stitchesPerCm = gaugeStitchesPerCm(values);

    final startWidthStitches = multiply(
      stitchesPerCm,
      values['startWidthCm'],
    )?.roundToDouble();
    final endWidthStitches = multiply(
      stitchesPerCm,
      values['endWidthCm'],
    )?.roundToDouble();
    final targetRows = multiply(
      gaugeRowsPerCm(values),
      values['targetLengthCm'],
    );

    final widthDiffStitches =
        (startWidthStitches ?? 0) - (endWidthStitches ?? 0);
    final isDecreasing = widthDiffStitches > 0;

    // One change on each side, so the total difference is halved.
    final changeCount = widthDiffStitches.abs() / 2;
    final changeRate = changeCount > 0 ? divide(targetRows, changeCount) : null;
    final isChangeRateFractional =
        changeRate != null &&
        !changeRate.isNaN &&
        !changeRate.isInfinite &&
        (changeRate - changeRate.roundToDouble()).abs() > 0.005;

    return [
      ...gaugeOutputs(values),
      ProductOutput(
        key: 'startWidthStitches',
        label: (l10n) => l10n.shawlStartWidthStitches,
        value: startWidthStitches,
      ),
      ProductOutput(
        key: 'endWidthStitches',
        label: (l10n) => l10n.shawlEndWidthStitches,
        value: endWidthStitches,
      ),
      ProductOutput(
        key: 'targetRows',
        label: (l10n) => l10n.targetRows,
        value: targetRows,
      ),
      ProductOutput(
        key: 'changeCount',
        label: (l10n) => isDecreasing
            ? l10n.shawlDecreasesPerSide
            : l10n.shawlIncreasesPerSide,
        value: changeCount,
      ),
      ProductOutput(
        key: 'changeRate',
        label: (l10n) =>
            isDecreasing ? l10n.shawlDecreaseRate : l10n.shawlIncreaseRate,
        value: changeRate,
        highlight: isChangeRateFractional,
      ),
    ];
  }
}
