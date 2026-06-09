import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/storage/photo_codec.dart';

/// Editable strip of attached photos, shared by the project editor and the
/// new-project save dialog so both behave identically: a leading "+" tile to
/// add more, then the photos newest-first as 96px thumbnails wrapping over up
/// to three rows. When they overflow, the last tile becomes a "+N more" overlay
/// that opens the full-screen viewer. Tapping a thumbnail opens that viewer;
/// hovering (or, on touch, always) reveals a delete button that confirms before
/// removing.
///
/// The strip is self-contained — it picks/encodes photos and shows the viewer
/// itself — and reports every change through [onChanged] so the parent can keep
/// its own copy (e.g. to persist or detect unsaved edits).
class PhotoStrip extends StatefulWidget {
  const PhotoStrip({super.key, required this.photos, required this.onChanged});

  /// The attached photos as base64 JPEG strings (see photo_codec.dart).
  final List<String> photos;

  /// Called with the new list whenever a photo is added or removed.
  final ValueChanged<List<String>> onChanged;

  @override
  State<PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<PhotoStrip> {
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

    widget.onChanged([...widget.photos, ...encoded]);
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
    widget.onChanged([...widget.photos]..removeAt(index));
  }

  /// Opens the tapped photo in a full-screen, pinch-to-zoom viewer that can page
  /// through the other attached photos and delete them. The viewer pages in the
  /// same newest-first order as the thumbnails, so swiping matches the strip;
  /// deletions are flipped back to storage order and reported through
  /// [widget.onChanged], keeping the strip and viewer in sync.
  void _openPhoto(int index, AppLocalizations l10n) {
    // Thumbnails are displayed newest-first (the strip walks indices in
    // reverse), so hand the viewer the reversed list and the matching position.
    final displayed = widget.photos.reversed.toList();
    final displayIndex = widget.photos.length - 1 - index;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => _PhotoViewer(
        photos: displayed,
        initialIndex: displayIndex,
        l10n: l10n,
        // The viewer reports the remaining photos in display (newest-first)
        // order; flip back to storage order before persisting.
        onChanged: (remaining) => widget.onChanged(remaining.reversed.toList()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 96px tiles with 8px gaps, wrapping onto new rows as they fill the width,
    // capped at three rows. When the photos don't fit, the last visible tile
    // becomes a "+N more" overlay instead of starting a fourth row.
    const tile = 96.0;
    const gap = 8.0;
    const maxRows = 3;

    // No card backing — the photo block sits flush on the page. Small padding
    // and a tight label gap keep the tiles close to the edges and the rows
    // starting right under the label, with a touch more at the bottom to
    // balance the divider/label gap at the top.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
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
          // by the Column (its cross-axis default).
          SizedBox(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Photos are stored oldest-first (appended on add); show them
                // newest-first by walking the indices in reverse.
                final order = [
                  for (var i = widget.photos.length - 1; i >= 0; i--) i,
                ];
                // How many tiles fit across the available width.
                final columns = ((constraints.maxWidth + gap) / (tile + gap))
                    .floor()
                    .clamp(1, 1 << 30);
                // Total tiles that fit in [maxRows], including the leading "+".
                final slots = columns * maxRows;
                // Slots left for photos after the leading "+".
                final photoSlots = slots - 1;
                final overflow = widget.photos.length > photoSlots;
                // On overflow the last slot shows the "+N more" tile, so one fewer
                // thumbnail is rendered; otherwise every photo gets its own tile.
                final shown = overflow ? photoSlots - 1 : widget.photos.length;

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
                        widget.photos.length - shown,
                        l10n,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The final tile when photos overflow the three-row cap: the next hidden
  /// photo ([firstHidden] is its index in [widget.photos]), darkened, with a
  /// "+N more" count. Tapping opens the viewer at that photo so the rest stay
  /// reachable.
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
          image: MemoryImage(_thumbnailBytes(widget.photos[firstHidden])),
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
                image: MemoryImage(_thumbnailBytes(widget.photos[index])),
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
}

/// Full-screen photo viewer shown over a black backdrop. Pinch to zoom (up to
/// 5x) and drag to pan via the [InteractiveViewer]; double-tap the photo to
/// zoom in on that point, double-tap again to fit. Tapping the backdrop around
/// the photo — or the close button — dismisses; a single tap on the photo
/// itself does nothing. When more than one photo is attached, left/right arrows
/// page through them (hidden at the ends). A delete button removes the current
/// photo (after confirming), pages to a neighbour, and closes when the last one
/// is gone; every change is reported through [onChanged].
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.l10n,
    required this.onChanged,
  });

  /// The attached photos as base64 JPEG strings (see photo_codec.dart).
  final List<String> photos;
  final int initialIndex;
  final AppLocalizations l10n;

  /// Called with the remaining photos whenever one is deleted from the viewer.
  final ValueChanged<List<String>> onChanged;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int _index = widget.initialIndex;

  /// Mutable copy of the attached photos so deletions update what the viewer
  /// pages through; the trimmed list is handed back to the parent via onChanged.
  late final List<String> _photos = [...widget.photos];

  /// Photos decoded once and cached, so paging reuses the same byte instances.
  /// Decoding inside [build] would hand [Image.memory] a fresh list each
  /// rebuild, defeating the image cache and re-decoding the JPEG — a blank
  /// frame that flickers while paging. Kept in step with [_photos] on delete.
  late final List<Uint8List> _decoded = [
    for (final photo in _photos) decodePhoto(photo),
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
    if (target < 0 || target >= _photos.length) {
      return;
    }
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Deletes the photo currently on screen after confirming. Reports the
  /// remaining photos to the parent, then pages to a neighbour — or closes the
  /// viewer when nothing is left.
  Future<void> _deleteCurrent() async {
    final l10n = widget.l10n;
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
    if (confirmed != true || !mounted) {
      return;
    }

    final removed = _index;
    setState(() {
      _photos.removeAt(removed);
      _decoded.removeAt(removed);
      // Reset zoom/pan so the photo sliding into view opens fit-to-screen.
      _transform.value = Matrix4.identity();
      if (_photos.isNotEmpty) {
        // Stay on the same slot (now showing the next photo); step back when the
        // last one was removed.
        _index = removed.clamp(0, _photos.length - 1);
      }
    });
    widget.onChanged([..._photos]);

    if (_photos.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    // Realign the controller to the new slot once the shorter PageView is laid
    // out (it can't be driven mid-rebuild).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(_index);
      }
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // While zoomed in, arrows pan the photo rather than paging, matching the
    // hidden chevrons and the disabled swipe physics.
    if (_zoomed) {
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
    // Hide every overlay control while zoomed in, so nothing covers the photo
    // being inspected; paging/keys are disabled to match (see _handleKey and the
    // PageView physics).
    final showControls = !_zoomed;
    final hasPrevious = showControls && _index > 0;
    final hasNext = showControls && _index < _photos.length - 1;

    // The default IconButton hover/press tint is dark — invisible on the black
    // backdrop — so paint a white translucent overlay for hover, focus and press.
    final overlayStyle = ButtonStyle(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return Colors.white24;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return Colors.white12;
        }
        return null;
      }),
    );

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
                  itemCount: _photos.length,
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
                  style: overlayStyle,
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
                  style: overlayStyle,
                  onPressed: () => _go(1),
                ),
              ),
            if (showControls)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: IconButton(
                  tooltip: l10n.removePhotoAction,
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  style: overlayStyle,
                  onPressed: _deleteCurrent,
                ),
              ),
            if (showControls)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  tooltip: l10n.closeAction,
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: overlayStyle,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
