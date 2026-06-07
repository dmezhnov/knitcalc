import 'package:flutter/material.dart';
import 'package:knitcalc/l10n/app_localizations.dart';

/// Asks the user for a project name. Returns the trimmed name, or `null` if the
/// dialog was cancelled or the field left blank.
Future<String?> promptProjectName(
  BuildContext context, {
  required String title,
  String? initial,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title, initial: initial),
  );

  return (name == null || name.isEmpty) ? null : name;
}

/// A single-field dialog for entering or editing a project name. It owns its
/// [TextEditingController] so the controller outlives the dialog's close
/// animation and is disposed only once the route is gone. Pops the trimmed text
/// on submit, or nothing on cancel.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.projectNameLabel),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.saveAction)),
      ],
    );
  }
}
