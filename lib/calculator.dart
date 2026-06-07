import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:knitcalc/account_menu.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/language_menu.dart';
import 'package:knitcalc/name_dialog.dart';
import 'package:knitcalc/products/products.dart';
import 'package:knitcalc/storage/photo_codec.dart';
import 'package:knitcalc/storage/projects_store.dart';
import 'package:knitcalc/storage/saved_project.dart';

/// Calculator screen: pick a product, enter the gauge and measurements, see the
/// computed result, and save it as a named project. Opened either for a fresh
/// draft ([initial] is `null`) or to edit an existing [SavedProject].
class Calculator extends StatefulWidget {
  const Calculator({
    super.key,
    required this.repository,
    this.initial,
    this.onSaved,
  });

  final ProjectsStore repository;

  /// The project being edited, or `null` for a new one.
  final SavedProject? initial;

  /// Called after a successful save, so a host showing this screen inline (the
  /// empty-state root) can refresh and reveal the now-populated list.
  final VoidCallback? onSaved;

  @override
  State<Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<Calculator> {
  late Product _product = widget.initial == null
      ? products.first
      : productById(widget.initial!.productId);

  /// One controller per input key, created lazily and kept for the lifetime of
  /// the screen so values survive switching between products.
  final Map<String, TextEditingController> _controllers = {};

  /// Free-text note, separate from the product inputs.
  late final TextEditingController _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );

  /// Attached photos as base64 JPEG strings (see photo_codec.dart).
  late List<String> _photos = [...?widget.initial?.photos];

  /// Identity of the saved project, or `null` until the first save. Once set,
  /// "Save" updates it in place instead of asking for a name again.
  late String? _currentId = widget.initial?.id;
  late String? _currentName = widget.initial?.name;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    // Pre-fill the fields when editing an existing project.
    final initial = widget.initial;
    if (initial != null) {
      for (final input in _product.inputs) {
        _controllerFor(input.key).text = initial.values[input.key] ?? '';
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _description.dispose();

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

  /// Raw field text for the active product, keyed by [ProductInput.key].
  Map<String, String> _currentValues() => {
    for (final input in _product.inputs)
      input.key: _controllerFor(input.key).text,
  };

  /// Saves the current fields. On the first save it asks for a name; afterwards
  /// it updates the loaded project in place.
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    var name = _currentName;

    if (name == null) {
      name = await promptProjectName(context, title: l10n.saveDialogTitle);

      if (name == null) {
        return;
      }
    }

    final existingId = _currentId;
    final project = existingId == null
        ? SavedProject.create(
            name: name,
            productId: _product.id,
            values: _currentValues(),
            description: _description.text.trim(),
            photos: _photos,
          )
        : SavedProject(
            id: existingId,
            name: name,
            productId: _product.id,
            values: _currentValues(),
            description: _description.text.trim(),
            photos: _photos,
            updatedAt: DateTime.now(),
          );

    await widget.repository.upsert(project);

    if (!mounted) {
      return;
    }

    setState(() {
      _currentId = project.id;
      _currentName = project.name;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.projectSavedSnack)));

    widget.onSaved?.call();
  }

  /// Lets the user pick one or more images, downscales and encodes them, and
  /// appends them to the attached photos.
  Future<void> _addPhotos() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) {
      return;
    }

    final encoded = <String>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      final photo = encodePhoto(bytes);
      if (photo != null) {
        encoded.add(photo);
      }
    }

    if (!mounted || encoded.isEmpty) {
      return;
    }

    setState(() => _photos = [..._photos, ...encoded]);
  }

  void _removePhoto(int index) {
    setState(() => _photos = [..._photos]..removeAt(index));
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
        title: Text(_currentName ?? l10n.newProjectTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: l10n.saveAction,
            onPressed: _save,
          ),
          const LanguageMenu(),
          const AccountMenu(),
        ],
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
                TextField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: l10n.descriptionLabel,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                _buildPhotos(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotos(AppLocalizations l10n) {
    return _buildCard(
      context,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.photosLabel),
            TextButton.icon(
              onPressed: _addPhotos,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(l10n.addPhotoAction),
            ),
          ],
        ),
        if (_photos.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _buildThumbnail(index, l10n),
            ),
          ),
      ],
    );
  }

  Widget _buildThumbnail(int index, AppLocalizations l10n) {
    return Stack(
      key: Key('photo_$index'),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            decodePhoto(_photos[index]),
            width: 96,
            height: 96,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: l10n.removePhotoAction,
            icon: const Icon(Icons.cancel, color: Colors.white),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: () => _removePhoto(index),
          ),
        ),
      ],
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
