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
  String get name => 'Треугольный палантин';

  @override
  List<ProductInput> get inputs => const [
    ...gaugeInputs,
    ProductInput(key: 'startWidthCm', label: 'Ширина в начале (см)'),
    ProductInput(key: 'endWidthCm', label: 'Ширина в конце (см)'),
    ProductInput(key: 'targetLengthCm', label: 'Желаемая длина (см)'),
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
        label: 'Петель в начале',
        value: startWidthStitches,
      ),
      ProductOutput(
        key: 'endWidthStitches',
        label: 'Петель в конце',
        value: endWidthStitches,
      ),
      ProductOutput(
        key: 'targetRows',
        label: 'Желаемое количество рядов',
        value: targetRows,
      ),
      ProductOutput(
        key: 'changeCount',
        label: isDecreasing
            ? 'Убавок с каждой стороны'
            : 'Прибавок с каждой стороны',
        value: changeCount,
      ),
      ProductOutput(
        key: 'changeRate',
        label: isDecreasing ? 'Темп убавок' : 'Темп прибавок',
        value: changeRate,
        highlight: isChangeRateFractional,
      ),
    ];
  }
}
