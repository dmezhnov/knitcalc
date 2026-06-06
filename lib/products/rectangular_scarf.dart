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
  String get name => 'Прямоугольный шарф';

  @override
  List<ProductInput> get inputs => const [
    ...gaugeInputs,
    ProductInput(key: 'targetWidthCm', label: 'Желаемая ширина (см)'),
    ProductInput(key: 'targetLengthCm', label: 'Желаемая длина (см)'),
    ProductInput(
      key: 'sampleWidthStitches',
      label: 'Ширина образца (петель)',
      allowDecimal: false,
    ),
    ProductInput(key: 'sampleThreadLengthCm', label: 'Длина нити образца (см)'),
    ProductInput(key: 'sampleThreadWidthCm', label: 'Ширина нити образца (см)'),
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
        label: 'Желаемое количество петель',
        value: targetStitches,
      ),
      ProductOutput(
        key: 'targetRows',
        label: 'Желаемое количество рядов',
        value: targetRows,
      ),
      ProductOutput(
        key: 'targetThreadLength',
        label: 'Желаемая длина нити',
        value: targetThreadLength,
      ),
    ];
  }
}
