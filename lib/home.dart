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
      return null;
    }

    return numerator / denominator;
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
    );
  }

  Widget _buildOutputRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stitches = _readNumber(_stitchesController);
    final rows = _readNumber(_rowsController);
    final sampleWidthCm = _readNumber(_sampleWidthCmController);
    final sampleLengthCm = _readNumber(_sampleLengthCmController);
    final sampleWidthStitches = _readNumber(_sampleWidthStitchesController);
    final targetWidthCm = _readNumber(_targetWidthCmController);
    final targetLengthCm = _readNumber(_targetLengthCmController);
    final sampleThreadLengthCm = _readNumber(_sampleThreadLengthCmController);

    final stitchesPerCm = _divide(stitches, sampleWidthCm);
    final rowsPerCm = _divide(rows, sampleLengthCm);
    final sampleThreadLengthPerStitch = _divide(
      sampleThreadLengthCm,
      sampleWidthStitches,
    );
    final targetStitches = stitchesPerCm == null || targetWidthCm == null
        ? null
        : stitchesPerCm * targetWidthCm;
    final targetRows = rowsPerCm == null || targetLengthCm == null
        ? null
        : rowsPerCm * targetLengthCm;
    final targetThreadLength =
        sampleThreadLengthPerStitch == null || stitches == null
        ? null
        : sampleThreadLengthPerStitch * stitches;

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
                      ),
                      _buildNumberInput(
                        label: 'Количество рядов',
                        allowDecimal: false,
                        controller: _rowsController,
                      ),
                      _buildNumberInput(
                        label: 'Ширина образца (см)',
                        allowDecimal: true,
                        controller: _sampleWidthCmController,
                      ),
                      _buildNumberInput(
                        label: 'Длина образца (см)',
                        allowDecimal: true,
                        controller: _sampleLengthCmController,
                      ),
                      _buildNumberInput(
                        label: 'Ширина образца (петель)',
                        allowDecimal: false,
                        controller: _sampleWidthStitchesController,
                      ),
                      _buildNumberInput(
                        label: 'Желаемая ширина (см)',
                        allowDecimal: true,
                        controller: _targetWidthCmController,
                      ),
                      _buildNumberInput(
                        label: 'Желаемая длина (см)',
                        allowDecimal: true,
                        controller: _targetLengthCmController,
                      ),
                      _buildNumberInput(
                        label: 'Длина нити образца (см)',
                        allowDecimal: true,
                        controller: _sampleThreadLengthCmController,
                      ),
                      _buildNumberInput(
                        label: 'Ширина нити образца (см)',
                        allowDecimal: true,
                        controller: _sampleThreadWidthCmController,
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
                      ),
                      _buildOutputRow(
                        label: 'Рядов в см',
                        value: _formatNumber(rowsPerCm),
                      ),
                      _buildOutputRow(
                        label: 'Желаемое количество петель',
                        value: _formatNumber(targetStitches),
                      ),
                      _buildOutputRow(
                        label: 'Желаемое количество рядов',
                        value: _formatNumber(targetRows),
                      ),
                      _buildOutputRow(
                        label: 'Желаемая длина нити',
                        value: _formatNumber(targetThreadLength),
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
