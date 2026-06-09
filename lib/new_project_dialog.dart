import 'package:flutter/material.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/photo_strip.dart';

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

  /// Attached photos as base64 JPEG strings (see photo_codec.dart). Owned here
  /// and handed to [PhotoStrip], which reports add/remove through its callback.
  List<String> _photos = [];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
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
              PhotoStrip(
                photos: _photos,
                onChanged: (photos) => setState(() => _photos = photos),
              ),
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
}
