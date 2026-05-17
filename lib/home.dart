import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _stitchesController = TextEditingController();
  final _rowsController = TextEditingController();
  final _sampleWidthCmController = TextEditingController();
  final _sampleLengthCmController = TextEditingController();
  final _sampleWidthStitchesController = TextEditingController();
  final _targetWidthCmController = TextEditingController();
  final _targetLengthCmController = TextEditingController();
  final _sampleThreadLengthCmController = TextEditingController();
  final _sampleThreadWidthCmController = TextEditingController();

  @override
  void initState() {
    super.initState();

    for (final controller in _controllers) {
      controller.addListener(_updateOutputs);
    }
  }

  List<TextEditingController> get _controllers => [
    _stitchesController,
    _rowsController,
    _sampleWidthCmController,
    _sampleLengthCmController,
    _sampleWidthStitchesController,
    _targetWidthCmController,
    _targetLengthCmController,
    _sampleThreadLengthCmController,
    _sampleThreadWidthCmController,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }

    super.dispose();
  }

  void _updateOutputs() {
    setState(() {});
  }

  double? _readNumber(TextEditingController controller) {
    final text = controller.text.trim().replaceAll(',', '.');

    if (text.isEmpty) {
      return null;
    }

    return double.tryParse(text);
  }

  double? _divide(double? numerator, double? denominator) {
    if (numerator == null || denominator == null || denominator == 0) {
      return 0;
    }

    return numerator / denominator;
  }

  double? _multiply(double? multiplicand, double? multiplier) {
    if (multiplicand == null || multiplier == null) {
      return 0.0;
    }

    return multiplicand * multiplier;
  }

  String _formatNumber(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return '-';
    }

    final rounded = value.toStringAsFixed(2);

    return rounded.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Widget _buildNumberInput({
    required String label,
    required bool allowDecimal,
    required TextEditingController controller,
    required Key key,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) {
          final pattern = allowDecimal ? r'^\d*([,.]\d*)?$' : r'^\d*$';

          if (RegExp(pattern).hasMatch(newValue.text)) {
            return newValue;
          }

          return oldValue;
        }),
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      key: key,
    );
  }

  Widget _buildOutputRow({
    required String label,
    required String value,
    required Key key,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      key: key,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stitches = _readNumber(_stitchesController); // Количество петель
    final sampleWidthCm = _readNumber(
      _sampleWidthCmController,
    ); // Ширина образца (см)
    final rows = _readNumber(_rowsController); // Количество рядов
    final sampleLengthCm = _readNumber(
      _sampleLengthCmController,
    ); // Длина образца (см)
    final targetWidthCm = _readNumber(
      _targetWidthCmController,
    ); // Желаемая ширина (см)
    final targetLengthCm = _readNumber(
      _targetLengthCmController,
    ); // Желаемая длина (см)
    final sampleWidthStitches = _readNumber(
      _sampleWidthStitchesController,
    ); // Ширина образца (петель)
    final sampleThreadLengthCm = _readNumber(
      _sampleThreadLengthCmController,
    ); // Длина нити образца (см)

    final stitchesPerCm = _divide(stitches, sampleWidthCm); //
    final rowsPerCm = _divide(rows, sampleLengthCm); //
    final sampleThreadLengthPerStitch = _divide(
      //
      sampleThreadLengthCm,
      sampleWidthStitches,
    );
    final targetStitches = _multiply(
      stitchesPerCm,
      targetWidthCm,
    ); // Желаемое количество петель
    final targetRows = _multiply(
      rowsPerCm,
      targetLengthCm,
    ); // Желаемое количество рядов
    final targetThreadLength = _multiply(
      sampleThreadLengthPerStitch,
      stitches,
    ); // Желаемая длина нити

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              spacing: 16,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: 'rectangular_scarf',
                  decoration: const InputDecoration(
                    labelText: 'Вид изделия',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'rectangular_scarf',
                      child: Text('Прямоугольный шарф'),
                    ),
                  ],
                  onChanged: null,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    spacing: 16,
                    children: [
                      _buildNumberInput(
                        label: 'Количество петель',
                        allowDecimal: false,
                        controller: _stitchesController,
                        key: const Key('stitches'),
                      ),
                      _buildNumberInput(
                        label: 'Ширина образца (см)',
                        allowDecimal: true,
                        controller: _sampleWidthCmController,
                        key: const Key('sampleWidthCm'),
                      ),
                      _buildNumberInput(
                        label: 'Количество рядов',
                        allowDecimal: false,
                        controller: _rowsController,
                        key: const Key('rows'),
                      ),
                      _buildNumberInput(
                        label: 'Длина образца (см)',
                        allowDecimal: true,
                        controller: _sampleLengthCmController,
                        key: const Key('sampleLengthCm'),
                      ),
                      _buildNumberInput(
                        label: 'Желаемая ширина (см)',
                        allowDecimal: true,
                        controller: _targetWidthCmController,
                        key: const Key('targetWidthCm'),
                      ),
                      _buildNumberInput(
                        label: 'Желаемая длина (см)',
                        allowDecimal: true,
                        controller: _targetLengthCmController,
                        key: const Key('targetLengthCm'),
                      ),
                      _buildNumberInput(
                        label: 'Ширина образца (петель)',
                        allowDecimal: false,
                        controller: _sampleWidthStitchesController,
                        key: const Key('sampleWidthStitches'),
                      ),
                      _buildNumberInput(
                        label: 'Длина нити образца (см)',
                        allowDecimal: true,
                        controller: _sampleThreadLengthCmController,
                        key: const Key('sampleThreadLengthCm'),
                      ),
                      _buildNumberInput(
                        label: 'Ширина нити образца (см)',
                        allowDecimal: true,
                        controller: _sampleThreadWidthCmController,
                        key: const Key('sampleThreadWidthCm'),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    spacing: 16,
                    children: [
                      _buildOutputRow(
                        label: 'Петель в см',
                        value: _formatNumber(stitchesPerCm),
                        key: const Key('stitchesPerCm'),
                      ),
                      _buildOutputRow(
                        label: 'Рядов в см',
                        value: _formatNumber(rowsPerCm),
                        key: const Key('rowsPerCm'),
                      ),
                      _buildOutputRow(
                        label: 'Желаемое количество петель',
                        value: _formatNumber(targetStitches),
                        key: const Key('targetStitches'),
                      ),
                      _buildOutputRow(
                        label: 'Желаемое количество рядов',
                        value: _formatNumber(targetRows),
                        key: const Key('targetRows'),
                      ),
                      _buildOutputRow(
                        label: 'Желаемая длина нити',
                        value: _formatNumber(targetThreadLength),
                        key: const Key('targetThreadLength'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
