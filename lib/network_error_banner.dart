import 'package:flutter/material.dart';
import 'package:knitcalc/l10n/app_localizations.dart';

/// Shows a top [MaterialBanner] reporting that a network operation — cloud sync
/// or the update check — could not reach its server, offering a Retry action.
///
/// It occupies the same slot as the update banner (a [ScaffoldMessenger] shows
/// one [MaterialBanner] at a time), so any current banner is hidden first.
/// UI strings are Russian to match the app.
ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>
showNetworkErrorBanner(BuildContext context, {required VoidCallback onRetry}) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);

  messenger.hideCurrentMaterialBanner();

  return messenger.showMaterialBanner(
    MaterialBanner(
      content: Text(l10n.networkErrorBanner),
      leading: const Icon(Icons.wifi_off),
      actions: [
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            onRetry();
          },
          child: Text(l10n.retryAction),
        ),
      ],
    ),
  );
}
