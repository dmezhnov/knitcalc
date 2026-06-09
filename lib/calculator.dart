import 'package:flutter/foundation.dart';
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

  // Snapshot of the last persisted content, used by [_isDirty] to warn before
  // leaving with unsaved edits. Refreshed on every successful save.
  late String _savedProductId = widget.initial?.productId ?? products.first.id;
  late Map<String, String> _savedValues = {...?widget.initial?.values};
  late String _savedDescription = widget.initial?.description ?? '';
  late List<String> _savedPhotos = [...?widget.initial?.photos];

  final ImagePicker _picker = ImagePicker();

  /// Index of the thumbnail the mouse is currently over, so its delete button
  /// shows only on hover (on touch platforms it always shows — there's no hover).
  int? _hoveredPhoto;

  /// Decoded thumbnail bytes cached per photo, so a rebuild (e.g. when hover
  /// toggles the delete button) reuses the same [Uint8List] instance. Decoding
  /// afresh each build hands [MemoryImage] a new instance — a cache miss that
  /// re-decodes the JPEG and flashes the thumbnail blank.
  final Map<String, Uint8List> _thumbnailCache = {};

  Uint8List _thumbnailBytes(String photo) =>
      _thumbnailCache.putIfAbsent(photo, () => decodePhoto(photo));

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

  Future<void> _removePhoto(int index, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePhotoConfirmTitle),
        content: Text(l10n.deletePhotoConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _photos = [..._photos]..removeAt(index));
  }

  /// Opens the tapped photo in a full-screen, pinch-to-zoom viewer that can page
  /// through the other attached photos.
  void _openPhoto(int index, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) =>
          _PhotoViewer(photos: _photos, initialIndex: index, l10n: l10n),
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
                  _buildPhotos(l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotos(AppLocalizations l10n) {
    // 96px tiles with 8px gaps, wrapping onto new rows as they fill the width,
    // capped at three rows. When the photos don't fit, the last visible tile
    // becomes a "+N more" overlay instead of starting a fourth row.
    const tile = 96.0;
    const gap = 8.0;
    const maxRows = 3;

    return _buildCard(
      context,
      // Tighter padding and label gap than the other cards so the photo tiles
      // sit close to the edges and the rows start right under the label. A bit
      // more at the bottom to balance the divider/label gap at the top.
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      spacing: 6,
      children: [
        // Centered section label with a rule running out to each side.
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(l10n.photosLabel),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        // Full width so a single short row left-aligns instead of being centered
        // by the card's Column (its cross-axis default).
        SizedBox(
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Photos are stored oldest-first (appended on add); show them
              // newest-first by walking the indices in reverse.
              final order = [for (var i = _photos.length - 1; i >= 0; i--) i];
              // How many tiles fit across the available width.
              final columns = ((constraints.maxWidth + gap) / (tile + gap))
                  .floor()
                  .clamp(1, 1 << 30);
              // Total tiles that fit in [maxRows], including the leading "+".
              final slots = columns * maxRows;
              // Slots left for photos after the leading "+".
              final photoSlots = slots - 1;
              final overflow = _photos.length > photoSlots;
              // On overflow the last slot shows the "+N more" tile, so one fewer
              // thumbnail is rendered; otherwise every photo gets its own tile.
              final shown = overflow ? photoSlots - 1 : _photos.length;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  // The "+" tile leads, so it's always reachable without scrolling.
                  _buildAddTile(l10n),
                  for (var i = 0; i < shown; i++)
                    _buildThumbnail(order[i], l10n),
                  if (overflow)
                    _buildOverflowTile(
                      order[shown],
                      _photos.length - shown,
                      l10n,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// The final tile when photos overflow the three-row cap: the next hidden
  /// photo ([firstHidden] is its index in [_photos]), darkened, with a "+N more"
  /// count. Tapping opens the viewer at that photo so the rest stay reachable.
  Widget _buildOverflowTile(
    int firstHidden,
    int remaining,
    AppLocalizations l10n,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        type: MaterialType.transparency,
        child: Ink.image(
          image: MemoryImage(_thumbnailBytes(_photos[firstHidden])),
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          child: InkWell(
            key: const Key('photos_overflow'),
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () => _openPhoto(firstHidden, l10n),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              color: Colors.black54,
              child: Text(
                l10n.morePhotos(remaining),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The trailing square in the photo strip: a large "+" that attaches photos
  /// when tapped. Sits after the thumbnails (or alone when none are attached).
  Widget _buildAddTile(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: l10n.addPhotoAction,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('add_photo'),
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: _addPhotos,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outline),
            ),
            child: Icon(Icons.add, size: 36, color: scheme.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(int index, AppLocalizations l10n) {
    final platform = Theme.of(context).platform;
    // Touch platforms have no hover, so always show the delete button there.
    final isTouch =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final showDelete = isTouch || _hoveredPhoto == index;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredPhoto = index),
      onExit: (_) => setState(() => _hoveredPhoto = null),
      child: Stack(
        key: Key('photo_$index'),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            // Ink.image paints the photo as the Material's decoration so the
            // InkWell's hover highlight/splash show *on top* of it; a plain
            // Image child would be opaque and hide the ink, leaving no visible
            // hover. InkWell already defaults to the clickable (hand) cursor.
            child: Material(
              type: MaterialType.transparency,
              child: Ink.image(
                image: MemoryImage(_thumbnailBytes(_photos[index])),
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                // InkWell falls back to the adaptive cursor (arrow on desktop),
                // so ask for the hand cursor explicitly like the button family.
                child: InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onTap: () => _openPhoto(index, l10n),
                ),
              ),
            ),
          ),
          if (showDelete)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: l10n.removePhotoAction,
                icon: const Icon(Icons.cancel, color: Colors.white),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => _removePhoto(index, l10n),
              ),
            ),
        ],
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

/// Full-screen photo viewer shown over a black backdrop. Pinch to zoom (up to
/// 5x) and drag to pan via the [InteractiveViewer]; double-tap the photo to
/// zoom in on that point, double-tap again to fit. Tapping the backdrop around
/// the photo — or the close button — dismisses; a single tap on the photo
/// itself does nothing. When more than one photo is attached, left/right arrows
/// page through them (hidden at the ends).
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.l10n,
  });

  /// The attached photos as base64 JPEG strings (see photo_codec.dart).
  final List<String> photos;
  final int initialIndex;
  final AppLocalizations l10n;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int _index = widget.initialIndex;

  /// Photos decoded once and cached, so paging reuses the same byte instances.
  /// Decoding inside [build] would hand [Image.memory] a fresh list each
  /// rebuild, defeating the image cache and re-decoding the JPEG — a blank
  /// frame that flickers while paging.
  late final List<Uint8List> _decoded = [
    for (final photo in widget.photos) decodePhoto(photo),
  ];

  /// Pages through the photos: native horizontal swipe, and the target of the
  /// arrow buttons / keyboard arrows via [_go].
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );

  /// Drives the current page's [InteractiveViewer] so double-tap can set the
  /// zoom directly. Reset on every page change so each photo opens fit.
  final TransformationController _transform = TransformationController();

  /// The [PageView]'s render box, used to map the double-tap's global position
  /// into the viewport (== scene at scale 1) so we zoom on that point.
  final GlobalKey _viewerKey = GlobalKey();

  /// Position of the last double-tap, captured on the down event because
  /// [GestureDetector.onDoubleTap] itself carries no coordinates.
  Offset? _doubleTapGlobal;

  /// True while the current photo is zoomed past fit. Disables paging swipes so
  /// a horizontal drag pans the zoomed photo instead of flipping the page.
  bool _zoomed = false;

  /// Scale a double-tap zooms to; pinch can still go further (up to maxScale).
  static const double _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onPageChanged(int index) {
    // Reset zoom/pan so the new photo opens fit-to-screen.
    _transform.value = Matrix4.identity();
    setState(() => _index = index);
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.photos.length) {
      return;
    }
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleDoubleTap() {
    // Already zoomed in → fit back to screen.
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _transform.value = Matrix4.identity();
      return;
    }

    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final global = _doubleTapGlobal;
    if (box == null || global == null) {
      return;
    }
    // At scale 1 the scene and viewport coincide, so the local point is the
    // scene point to keep fixed while scaling around it.
    final focal = box.globalToLocal(global);
    _transform.value = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final hasPrevious = _index > 0;
    final hasNext = _index < widget.photos.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Autofocus so the left/right arrow keys page without an extra click.
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            Positioned.fill(
              // Tap on the backdrop dismisses. The inner GestureDetector around
              // each photo absorbs taps (it wins the gesture arena as the deeper
              // hit), so tapping the photo itself does not close the viewer.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: PageView.builder(
                  key: _viewerKey,
                  controller: _pageController,
                  // While zoomed, a horizontal drag should pan the photo, so
                  // stop the PageView from claiming it to flip the page.
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  onPageChanged: _onPageChanged,
                  itemCount: widget.photos.length,
                  itemBuilder: (context, i) {
                    return InteractiveViewer(
                      // Only the visible page drives the shared controller; the
                      // off-screen neighbours keep their own (fit) transform.
                      transformationController: i == _index ? _transform : null,
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: GestureDetector(
                          // Absorb single taps (so the backdrop's dismiss
                          // doesn't fire on the photo) and zoom on double-tap.
                          onTap: () {},
                          onDoubleTapDown: (d) =>
                              _doubleTapGlobal = d.globalPosition,
                          onDoubleTap: _handleDoubleTap,
                          // Keep the previous frame until the next is ready so
                          // paging doesn't flash blank between photos.
                          child: Image.memory(
                            _decoded[i],
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (hasPrevious)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: l10n.previousPhotoAction,
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  iconSize: 40,
                  onPressed: () => _go(-1),
                ),
              ),
            if (hasNext)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: l10n.nextPhotoAction,
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  iconSize: 40,
                  onPressed: () => _go(1),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                tooltip: l10n.closeAction,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
