import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/storage/photo_codec.dart';

/// Everything collected when first saving a fresh project: besides the required
/// [name], the user can write a [description] and attach [photos] right from the
/// save dialog, so a brand-new item is fully described in one step.
class NewProjectDetails {
  const NewProjectDetails({
    required this.name,
    required this.description,
    required this.photos,
  });

  final String name;
  final String description;
  final List<String> photos;
}

/// Asks for a new project's name, description and photos in a single dialog.
/// Returns the collected details, or `null` if the dialog was cancelled. The
/// name is required, so the Save button stays disabled until it's filled in.
Future<NewProjectDetails?> promptNewProjectDetails(
  BuildContext context, {
  required String title,
}) {
  return showDialog<NewProjectDetails>(
    context: context,
    builder: (context) => _NewProjectDialog(title: title),
  );
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.title});

  final String title;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  /// Attached photos as base64 JPEG strings (see photo_codec.dart).
  final List<String> _photos = [];

  /// Decoded thumbnail bytes cached per photo, so a rebuild reuses the same
  /// [Uint8List] instance instead of re-decoding the JPEG (a cache miss that
  /// flashes the thumbnail blank).
  final Map<String, Uint8List> _thumbnailCache = {};

  Uint8List _thumbnailBytes(String photo) =>
      _thumbnailCache.putIfAbsent(photo, () => decodePhoto(photo));

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

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

    setState(() => _photos.addAll(encoded));
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      NewProjectDetails(
        name: name,
        description: _description.text.trim(),
        photos: _photos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canSave = _name.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.projectNameLabel),
                // Rebuild so the Save button enables once a name is typed.
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        TextButton(
          onPressed: canSave ? _submit : null,
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }

  Widget _buildPhotos(AppLocalizations l10n) {
    const tile = 72.0;

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // The "+" tile leads; photos follow newest-first.
          _buildAddTile(l10n, tile),
          for (var i = _photos.length - 1; i >= 0; i--)
            _buildThumbnail(i, tile, l10n),
        ],
      ),
    );
  }

  Widget _buildAddTile(AppLocalizations l10n, double tile) {
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
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outline),
            ),
            child: Icon(Icons.add, size: 28, color: scheme.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(int index, double tile, AppLocalizations l10n) {
    return Stack(
      key: Key('photo_$index'),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            _thumbnailBytes(_photos[index]),
            width: tile,
            height: tile,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: l10n.removePhotoAction,
            icon: const Icon(Icons.cancel, color: Colors.white),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: () => _removePhoto(index),
          ),
        ),
      ],
    );
  }
}
