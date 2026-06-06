import 'package:flutter/material.dart';
import 'package:knitcalc/update/ui/byte_format.dart';
import 'package:knitcalc/update/update_info.dart';

/// Banner text: announces the new version and, when known, how much the update
/// will download (e.g. "Доступна новая версия 1.5.0 · 12 МБ").
String _bannerText(UpdateInfo info) {
  final size = info.downloadSize;
  final suffix = size != null ? ' · ${formatBytes(size)}' : '';
  return 'Доступна новая версия ${info.latestVersion}$suffix';
}

/// Non-intrusive banner offering the user an available update.
///
/// Shown via [showUpdateBanner]. For a mandatory update the dismiss action is
/// hidden so only "update" remains. UI strings are in Russian to match the app.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.info,
    required this.onUpdate,
    this.onDismiss,
  });

  final UpdateInfo info;
  final VoidCallback onUpdate;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(_bannerText(info)),
      leading: const Icon(Icons.system_update),
      actions: [
        if (!info.mandatory && onDismiss != null)
          TextButton(onPressed: onDismiss, child: const Text('Позже')),
        TextButton(onPressed: onUpdate, child: const Text('Обновить')),
      ],
    );
  }
}

/// Shows an [UpdateBanner] in the nearest [ScaffoldMessenger].
///
/// Returns the controller so the caller can hide the banner once the update
/// flow starts or is dismissed.
ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>
showUpdateBanner(
  BuildContext context, {
  required UpdateInfo info,
  required VoidCallback onUpdate,
  VoidCallback? onDismiss,
}) {
  final messenger = ScaffoldMessenger.of(context);

  return messenger.showMaterialBanner(
    MaterialBanner(
      content: Text(_bannerText(info)),
      leading: const Icon(Icons.system_update),
      actions: [
        if (!info.mandatory && onDismiss != null)
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              onDismiss();
            },
            child: const Text('Позже'),
          ),
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            onUpdate();
          },
          child: const Text('Обновить'),
        ),
      ],
    ),
  );
}
