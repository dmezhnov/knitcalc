import 'package:flutter/material.dart';
import 'package:knitcalc/account_avatar.dart';
import 'package:knitcalc/auth_screen.dart';
import 'package:knitcalc/firebase/auth_scope.dart';
import 'package:knitcalc/l10n/app_localizations.dart';

/// App-bar action for the cloud account. Signed out it offers sign-in; signed in
/// (and verified — an unverified account never reaches the app) it shows the
/// email and a sign-out item. Rebuilds with [AuthScope] when the session
/// changes.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key, this.onSync});

  /// When provided (and signed in), adds a "Sync" item that runs this — used by
  /// the project list to re-sync with the cloud. Omitted where there's nothing
  /// to sync (e.g. the calculator screen).
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);

    if (!auth.isSignedIn) {
      return IconButton(
        icon: const Icon(Icons.account_circle_outlined),
        tooltip: l10n.signInAction,
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<bool>(builder: (_) => const AuthScreen())),
      );
    }

    final photoUrl = auth.photoUrl;

    return PopupMenuButton<void>(
      icon: photoUrl == null
          ? const Icon(Icons.account_circle)
          : buildAccountAvatar(photoUrl, 14),
      tooltip: auth.email,
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            auth.email ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const PopupMenuDivider(),
        if (onSync != null)
          PopupMenuItem(onTap: onSync, child: Text(l10n.syncAction)),
        PopupMenuItem(onTap: auth.signOut, child: Text(l10n.signOutAction)),
      ],
    );
  }
}
