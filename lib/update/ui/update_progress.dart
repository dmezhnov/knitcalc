import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/ui/byte_format.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// Runs [UpdateService.startUpdate] behind a shared progress dialog.
///
/// Both channels go through the same flow: a modal dialog shows the download
/// progress (a percentage on Android, an indeterminate bar on web, where the
/// browser reloads and refetches the assets itself), with Pause and Cancel
/// controls. On failure the dialog is dismissed and a snackbar is shown.
Future<void> runUpdateWithProgress(
  BuildContext context,
  UpdateService service,
  UpdateInfo info,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final l10n = AppLocalizations.of(context);
  final progress = ValueNotifier<DownloadProgress?>(null);
  final control = DownloadControl();

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateProgressDialog(
        progress: progress,
        onCancel: control.cancel,
        onPause: control.pause,
        onResume: control.resume,
        pausedListenable: control.pausedListenable,
      ),
    ),
  );

  var failed = false;

  try {
    await service.startUpdate(
      info,
      onProgress: (value) => progress.value = value,
      control: control,
    );
  } on UpdateCancelled {
    // The user cancelled the download; not a failure, so no error snackbar.
    // The caller re-shows the update banner once this returns.
  } on Object {
    failed = true;
  }

  if (navigator.canPop()) {
    navigator.pop();
  }

  progress.dispose();
  control.dispose();

  if (failed) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.updateFailed)));
  }
}

/// Modal dialog showing update download progress with Pause and Cancel.
///
/// [onCancel] aborts the download; the dialog is dismissed by the caller once
/// the cancelled download returns. A back-press routes to the same cancel so a
/// dismissed dialog never leaves the download running silently. [onPause] /
/// [onResume] (driven by [pausedListenable]) suspend and continue the transfer
/// in place.
class UpdateProgressDialog extends StatelessWidget {
  const UpdateProgressDialog({
    super.key,
    required this.progress,
    this.onCancel,
    this.onPause,
    this.onResume,
    this.pausedListenable,
  });

  final ValueListenable<DownloadProgress?> progress;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final ValueListenable<bool>? pausedListenable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final paused = pausedListenable ?? const _AlwaysFalse();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onCancel?.call();
      },
      child: AlertDialog(
        title: Text(l10n.updateDownloadTitle),
        actions: [
          if (onPause != null && onResume != null)
            ValueListenableBuilder<bool>(
              valueListenable: paused,
              builder: (context, isPaused, _) => TextButton(
                onPressed: isPaused ? onResume : onPause,
                child: Text(isPaused ? l10n.updateResume : l10n.updatePause),
              ),
            ),
          if (onCancel != null)
            TextButton(onPressed: onCancel, child: Text(l10n.cancelAction)),
        ],
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
                ValueListenableBuilder<bool>(
                  valueListenable: paused,
                  builder: (context, isPaused, _) {
                    final status = isPaused
                        ? l10n.updatePaused
                        : (percent == null
                              ? l10n.updatePreparing
                              : '$percent%');
                    return Text(status, textAlign: TextAlign.center);
                  },
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
      ),
    );
  }
}

/// A constant `false` listenable used when the dialog is shown without pause
/// support, so the status/button builders can subscribe unconditionally.
class _AlwaysFalse implements ValueListenable<bool> {
  const _AlwaysFalse();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
