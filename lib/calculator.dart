import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knitcalc/account_menu.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/language_menu.dart';
import 'package:knitcalc/new_project_dialog.dart';
import 'package:knitcalc/photo_strip.dart';
import 'package:knitcalc/products/products.dart';
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

  // Snapshot of the last persisted content, used by [_isDirty] to warn before
  // leaving with unsaved edits. Refreshed on every successful save.
  late String _savedProductId = widget.initial?.productId ?? products.first.id;
  late Map<String, String> _savedValues = {...?widget.initial?.values};
  late String _savedDescription = widget.initial?.description ?? '';
  late List<String> _savedPhotos = [...?widget.initial?.photos];

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

  /// Saves the current fields. The first save of a fresh draft asks for the
  /// name, description and photos in one dialog (the inline description/photo
  /// fields stay hidden until then); afterwards it updates the loaded project
  /// in place using the now-visible inline fields.
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);

    final existingId = _currentId;
    final String name;
    final String description;
    final List<String> photos;

    if (existingId == null) {
      final details = await promptNewProjectDetails(
        context,
        title: l10n.saveDialogTitle,
      );
      if (details == null) {
        return;
      }
      name = details.name;
      description = details.description;
      photos = details.photos;
    } else {
      name = _currentName!;
      description = _description.text.trim();
      photos = _photos;
    }

    final project = existingId == null
        ? SavedProject.create(
            name: name,
            productId: _product.id,
            values: _currentValues(),
            description: description,
            photos: photos,
          )
        : SavedProject(
            id: existingId,
            name: name,
            productId: _product.id,
            values: _currentValues(),
            description: description,
            photos: photos,
            updatedAt: DateTime.now(),
          );

    await widget.repository.upsert(project);

    if (!mounted) {
      return;
    }

    setState(() {
      _currentId = project.id;
      _currentName = project.name;
      // Adopt what the new-project dialog collected so the now-visible inline
      // fields show it (a no-op when updating an existing project in place).
      _description.text = project.description;
      _photos = [...project.photos];
      // The current content is now the persisted baseline (see _isDirty).
      _savedProductId = project.productId;
      _savedValues = {...project.values};
      _savedDescription = project.description;
      _savedPhotos = [...project.photos];
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.projectSavedSnack)));

    widget.onSaved?.call();
  }

  /// Whether the editable content differs from the last persisted snapshot.
  /// Empty input fields are treated as absent so a fresh draft isn't "dirty"
  /// just for having blank fields.
  bool _isDirty() {
    if (_product.id != _savedProductId) {
      return true;
    }
    if (_description.text.trim() != _savedDescription) {
      return true;
    }
    if (!listEquals(_photos, _savedPhotos)) {
      return true;
    }
    return !mapEquals(_nonEmpty(_currentValues()), _nonEmpty(_savedValues));
  }

  Map<String, String> _nonEmpty(Map<String, String> values) => {
    for (final entry in values.entries)
      if (entry.value.trim().isNotEmpty) entry.key: entry.value,
  };

  /// Asks what to do about unsaved edits when leaving the editor: stay, leave
  /// discarding them, or save first. Returns null (== stay) if dismissed.
  Future<_ExitChoice?> _promptOnExit(AppLocalizations l10n) {
    return showDialog<_ExitChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.unsavedChangesTitle),
        content: Text(l10n.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.cancel),
            child: Text(l10n.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.discard),
            child: Text(l10n.discardAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.save),
            child: Text(l10n.saveAndExitAction),
          ),
        ],
      ),
    );
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

    return PopScope(
      // Block the back button / gesture while there are unsaved edits, then ask
      // whether to discard them before actually leaving the editor.
      canPop: !_isDirty(),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final navigator = Navigator.of(context);
        final choice = await _promptOnExit(l10n);
        if (choice == null || choice == _ExitChoice.cancel || !mounted) {
          return;
        }
        if (choice == _ExitChoice.save) {
          await _save();
          // A cancelled name prompt (new project) leaves us still dirty; only
          // leave once the save actually went through.
          if (!mounted || _isDirty()) {
            return;
          }
        }
        navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_currentName ?? l10n.newProjectTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: l10n.saveAction,
              // Disabled (greyed out) when nothing changed, except for a draft
              // that has never been saved — that first save is always allowed.
              onPressed: _currentId == null || _isDirty() ? _save : null,
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
                  // The description and photos belong to a saved item: a fresh
                  // draft collects them in the save dialog, so they only appear
                  // inline once the project exists. Shown first: photos, then
                  // the description, then the product picker and its fields.
                  if (_currentId != null) ...[
                    PhotoStrip(
                      photos: _photos,
                      onChanged: (photos) => setState(() => _photos = photos),
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
                      // Rebuild so the save button reflects unsaved changes.
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _product.id,
                    // Match the rest of the button family: hand cursor on desktop,
                    // not the platform-adaptive default (arrow on desktop).
                    // mouseCursor is the closed trigger; dropdownMenuItemMouseCursor
                    // is the items in the open popup (each its own InkWell).
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    dropdownMenuItemMouseCursor:
                        WidgetStateMouseCursor.clickable,
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
                      for (final output in outputs)
                        _buildOutputRow(output, l10n),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required List<Widget> children,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double spacing = 16,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(spacing: spacing, children: children),
    );
  }
}

/// What to do with unsaved edits when leaving the editor (see [_promptOnExit]).
enum _ExitChoice { cancel, discard, save }
