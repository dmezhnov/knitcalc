import 'package:flutter/material.dart';
import 'package:knitcalc/l10n/app_localizations.dart';

/// Shows a top [MaterialBanner] reporting that a network operation — cloud sync
/// or the update check — could not reach its server, offering a Retry action.
///
/// It occupies the same slot as the update banner (a [ScaffoldMessenger] shows
/// one [MaterialBanner] at a time), so any current banner is hidden first.
///
/// The texts are resolved inside [Builder]s rather than captured here, so a
/// banner that is already on screen follows a runtime language switch (the
/// ScaffoldMessenger rebuilds it under the new [Localizations]) instead of
/// staying in the language it was shown in.
ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>
showNetworkErrorBanner(BuildContext context, {required VoidCallback onRetry}) {
  final messenger = ScaffoldMessenger.of(context);

  messenger.hideCurrentMaterialBanner();

  return messenger.showMaterialBanner(
    MaterialBanner(
      content: Builder(
        builder: (context) =>
            Text(AppLocalizations.of(context).networkErrorBanner),
      ),
      leading: const Icon(Icons.wifi_off),
      actions: [
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              onRetry();
            },
            child: Text(AppLocalizations.of(context).retryAction),
          ),
        ),
      ],
    ),
  );
}
