/// Shared knitting-gauge building block reused by every product.
///
/// Every product starts from a swatch: a known number of stitches over a known
/// width and a known number of rows over a known length. From that we derive
/// stitches-per-cm and rows-per-cm, which drive all further calculations.
library;

import 'product.dart';

/// Inputs describing the knitted swatch. Reused at the top of every product's
/// [Product.inputs] list.
const List<ProductInput> gaugeInputs = [
  ProductInput(
    key: 'stitches',
    label: 'Количество петель',
    allowDecimal: false,
  ),
  ProductInput(key: 'sampleWidthCm', label: 'Ширина образца (см)'),
  ProductInput(key: 'rows', label: 'Количество рядов', allowDecimal: false),
  ProductInput(key: 'sampleLengthCm', label: 'Длина образца (см)'),
];

/// Stitches per centimetre derived from the swatch.
double? gaugeStitchesPerCm(Map<String, double?> values) =>
    divide(values['stitches'], values['sampleWidthCm']);

/// Rows per centimetre derived from the swatch.
double? gaugeRowsPerCm(Map<String, double?> values) =>
    divide(values['rows'], values['sampleLengthCm']);

/// Outputs describing the gauge. Reused at the top of every product's
/// [Product.computeOutputs] result.
List<ProductOutput> gaugeOutputs(Map<String, double?> values) => [
  ProductOutput(
    key: 'stitchesPerCm',
    label: 'Петель в см',
    value: gaugeStitchesPerCm(values),
  ),
  ProductOutput(
    key: 'rowsPerCm',
    label: 'Рядов в см',
    value: gaugeRowsPerCm(values),
  ),
];
