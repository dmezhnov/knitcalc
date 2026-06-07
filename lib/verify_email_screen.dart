import 'package:flutter/material.dart';
import 'package:knitcalc/firebase/auth_scope.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/language_menu.dart';

/// Gate shown while the signed-in user's email is unconfirmed. The app is not
/// usable until the verification link is opened; from here the user can re-check
/// ("I've verified"), resend the email, or sign out. It clears itself once
/// [AuthService.reloadEmailVerified] reports the address as verified (the auth
/// notifier then rebuilds the root past this screen).
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = false;

  Future<void> _checkVerified() async {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);

    setState(() => _busy = true);
    final verified = await auth.reloadEmailVerified();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    // When verified, the auth notifier rebuilds the root and this screen is
    // replaced automatically; otherwise nudge the user.
    if (!verified) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.notVerifiedYetSnack)));
    }
  }

  Future<void> _resend() async {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);

    try {
      await auth.sendVerificationEmail();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.verifyEmailResentSnack)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.authErrorGeneric)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.verifyEmailSentTitle),
        actions: const [LanguageMenu()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 64),
                  Text(
                    l10n.verifyEmailSentMessage(auth.email ?? ''),
                    textAlign: TextAlign.center,
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _checkVerified,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.iVerifiedAction),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _resend,
                    child: Text(l10n.resendEmailAction),
                  ),
                  TextButton(
                    onPressed: _busy ? null : auth.signOut,
                    child: Text(l10n.signOutAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
