import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  final progress = ValueNotifier<double?>(null);

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
      onProgress: (fraction) => progress.value = fraction,
    );
  } on Object {
    failed = true;
  }

  if (navigator.canPop()) {
    navigator.pop();
  }

  progress.dispose();

  if (failed) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Не удалось загрузить обновление')),
    );
  }
}

/// Modal dialog showing update download progress.
class UpdateProgressDialog extends StatelessWidget {
  const UpdateProgressDialog({super.key, required this.progress});

  final ValueListenable<double?> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Загрузка обновления'),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (context, value, _) {
          final percent = value == null
              ? null
              : (value.clamp(0.0, 1.0) * 100).round();

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              Text(
                percent == null ? 'Подготовка…' : '$percent%',
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
