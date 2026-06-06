import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/update/ui/byte_format.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// Runs [UpdateService.startUpdate] behind a shared progress dialog.
///
/// Both channels go through the same flow: a modal dialog shows the download
/// progress (a percentage on Android, an indeterminate bar on web, where the
/// browser reloads and refetches the assets itself). On failure the dialog is
/// dismissed and a snackbar is shown.
Future<void> runUpdateWithProgress(
  BuildContext context,
  UpdateService service,
  UpdateInfo info,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final l10n = AppLocalizations.of(context);
  final progress = ValueNotifier<DownloadProgress?>(null);

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateProgressDialog(progress: progress),
    ),
  );

  var failed = false;

  try {
    await service.startUpdate(
      info,
      onProgress: (value) => progress.value = value,
    );
  } on Object {
    failed = true;
  }

  if (navigator.canPop()) {
    navigator.pop();
  }

  progress.dispose();

  if (failed) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.updateFailed)));
  }
}

/// Modal dialog showing update download progress.
class UpdateProgressDialog extends StatelessWidget {
  const UpdateProgressDialog({super.key, required this.progress});

  final ValueListenable<DownloadProgress?> progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.updateDownloadTitle),
      content: ValueListenableBuilder<DownloadProgress?>(
        valueListenable: progress,
        builder: (context, value, _) {
          final fraction = value?.fraction;
          final percent = fraction == null ? null : (fraction * 100).round();

          // "3.4 / 12 МБ" once a total is known; nothing until the first chunk.
          final downloaded = (value != null && value.total > 0)
              ? '${l10n.formatBytes(value.received)} / ${l10n.formatBytes(value.total)}'
              : null;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: fraction),
              const SizedBox(height: 12),
              Text(
                percent == null ? l10n.updatePreparing : '$percent%',
                textAlign: TextAlign.center,
              ),
              if (downloaded != null) ...[
                const SizedBox(height: 4),
                Text(
                  downloaded,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
