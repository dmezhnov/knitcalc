import 'gauge.dart';
import 'product.dart';

/// Прямоугольный шарф — a rectangle of constant width and length.
///
/// Beyond the gauge, the user supplies the target width and length plus an
/// extra swatch measured by thread, which lets us estimate the total thread
/// length needed.
class RectangularScarf extends Product {
  const RectangularScarf();

  @override
  String get id => 'rectangular_scarf';

  @override
  LocalizedString get name =>
      (l10n) => l10n.productRectangularScarf;

  @override
  List<ProductInput> get inputs => [
    ...gaugeInputs,
    ProductInput(
      key: 'targetWidthCm',
      label: (l10n) => l10n.scarfTargetWidthCm,
    ),
    ProductInput(key: 'targetLengthCm', label: (l10n) => l10n.targetLengthCm),
    ProductInput(
      key: 'sampleWidthStitches',
      label: (l10n) => l10n.scarfSampleWidthStitches,
      allowDecimal: false,
    ),
    ProductInput(
      key: 'sampleThreadLengthCm',
      label: (l10n) => l10n.scarfSampleThreadLengthCm,
    ),
    ProductInput(
      key: 'sampleThreadWidthCm',
      label: (l10n) => l10n.scarfSampleThreadWidthCm,
    ),
  ];

  @override
  List<ProductOutput> computeOutputs(Map<String, double?> values) {
    final targetStitches = multiply(
      gaugeStitchesPerCm(values),
      values['targetWidthCm'],
    );
    final targetRows = multiply(
      gaugeRowsPerCm(values),
      values['targetLengthCm'],
    );

    final threadLengthPerStitch = divide(
      values['sampleThreadLengthCm'],
      values['sampleWidthStitches'],
    );
    final targetThreadLength = multiply(
      threadLengthPerStitch,
      values['stitches'],
    );

    return [
      ...gaugeOutputs(values),
      ProductOutput(
        key: 'targetStitches',
        label: (l10n) => l10n.scarfTargetStitches,
        value: targetStitches,
      ),
      ProductOutput(
        key: 'targetRows',
        label: (l10n) => l10n.targetRows,
        value: targetRows,
      ),
      ProductOutput(
        key: 'targetThreadLength',
        label: (l10n) => l10n.scarfTargetThreadLength,
        value: targetThreadLength,
      ),
    ];
  }
}
