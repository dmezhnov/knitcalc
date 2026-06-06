import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/l10n/language.dart';
import 'package:knitcalc/l10n/locale_scope.dart';
import 'package:knitcalc/products/products.dart';
import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/ui/update_banner.dart';
import 'package:knitcalc/update/ui/update_progress.dart';
import 'package:knitcalc/update/update_factory.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Product _product = products.first;

  /// One controller per input key, created lazily and kept for the lifetime of
  /// the screen so values survive switching between products.
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();

    // Check for an update once the first frame is on screen. Off the web target
    // the factory returns a no-op service, so this is harmless there.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final channel = await detectChannel();
    final service = createUpdateService(channel);
    final info = await service.checkForUpdate();

    if (info == null || !mounted) {
      return;
    }

    showUpdateBanner(
      context,
      info: info,
      onUpdate: () => runUpdateWithProgress(context, service, info),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  TextEditingController _controllerFor(String key) =>
      _controllers.putIfAbsent(key, () {
        final controller = TextEditingController();
        controller.addListener(_updateOutputs);
        return controller;
      });

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

  String _formatNumber(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return '-';
    }

    final rounded = value.toStringAsFixed(2);

    return rounded.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Widget _buildNumberInput(ProductInput input, AppLocalizations l10n) {
    return TextFormField(
      controller: _controllerFor(input.key),
      keyboardType: TextInputType.numberWithOptions(
        decimal: input.allowDecimal,
      ),
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) {
          final pattern = input.allowDecimal ? r'^\d*([,.]\d*)?$' : r'^\d*$';

          if (RegExp(pattern).hasMatch(newValue.text)) {
            return newValue;
          }

          return oldValue;
        }),
      ],
      decoration: InputDecoration(
        labelText: input.label(l10n),
        border: const OutlineInputBorder(),
      ),
      key: Key(input.key),
    );
  }

  Widget _buildOutputRow(ProductOutput output, AppLocalizations l10n) {
    final color = output.highlight ? Colors.red : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      key: Key(output.key),
      children: [
        Expanded(
          child: Text(output.label(l10n), style: TextStyle(color: color)),
        ),
        const SizedBox(width: 16),
        Text(
          _formatNumber(output.value),
          style: TextStyle(fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }

  Widget _buildLanguageMenu() {
    final controller = LocaleScope.of(context);

    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.language),
      tooltip: languageName(controller.value),
      initialValue: controller.value,
      onSelected: (locale) => controller.value = locale,
      itemBuilder: (context) => [
        for (final locale in AppLocalizations.supportedLocales)
          CheckedPopupMenuItem(
            value: locale,
            checked: locale.languageCode == controller.value.languageCode,
            child: Text(languageName(locale)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final values = {
      for (final input in _product.inputs)
        input.key: _readNumber(_controllerFor(input.key)),
    };
    final outputs = _product.computeOutputs(values);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KnitCalc'),
        actions: [_buildLanguageMenu()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            // Leave room above the first field so its floating outline label
            // isn't clipped by the scroll view's viewport edge.
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              spacing: 16,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _product.id,
                  decoration: InputDecoration(
                    labelText: l10n.productKindLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final product in products)
                      DropdownMenuItem(
                        value: product.id,
                        child: Text(product.name(l10n)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _product = productById(value));
                    }
                  },
                ),
                _buildCard(
                  context,
                  children: [
                    for (final input in _product.inputs)
                      _buildNumberInput(input, l10n),
                  ],
                ),
                _buildCard(
                  context,
                  children: [
                    for (final output in outputs) _buildOutputRow(output, l10n),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(spacing: 16, children: children),
    );
  }
}
