import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knitcalc/firebase/auth_scope.dart';
import 'package:knitcalc/firebase/firebase_auth_client.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/language_menu.dart';

/// Email/password sign-in and registration screen. Both pop with the user
/// signed in; for a new account a verification email is sent and the root then
/// shows the verification gate until the address is confirmed.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  /// Whether the form registers a new account rather than signing in.
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.authErrorGeneric);
      return;
    }

    if (_register && password != _passwordConfirm.text) {
      setState(() => _error = l10n.authErrorPasswordMismatch);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_register) {
        await auth.signUp(email, password);
      } else {
        await auth.signIn(email, password);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _messageFor(e.code, l10n));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.authErrorGeneric);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await auth.signInWithGoogle();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on PlatformException catch (e) {
      // A user-dismissed browser sheet is not an error; anything else is.
      if (mounted) {
        setState(() {
          _error = e.code == 'CANCELED' ? null : '${l10n.authErrorGeneric}: $e';
          _busy = false;
        });
      }
    } catch (e, stack) {
      debugPrint('Google sign-in failed: $e\n$stack');
      if (mounted) {
        setState(() {
          _error = '${l10n.authErrorGeneric}: $e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);

    final email = await showDialog<String>(
      context: context,
      builder: (context) => _ResetPasswordDialog(initial: _email.text.trim()),
    );

    if (email == null || email.isEmpty) {
      return;
    }

    try {
      await auth.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.resetEmailSentSnack)));
      }
    } on FirebaseAuthException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.authErrorGeneric)));
      }
    }
  }

  String _messageFor(String code, AppLocalizations l10n) {
    switch (code) {
      case 'EMAIL_EXISTS':
        return l10n.authErrorEmailExists;
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_PASSWORD':
        return l10n.authErrorInvalidCredentials;
      case 'WEAK_PASSWORD':
        return l10n.authErrorWeakPassword;
      case 'INVALID_EMAIL':
      case 'MISSING_EMAIL':
        return l10n.authErrorInvalidEmail;
      default:
        return l10n.authErrorGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _register ? l10n.registerTitle : l10n.signInTitle;

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [LanguageMenu()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _buildForm(l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        TextField(
          key: const Key('auth_email'),
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: l10n.emailLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        TextField(
          key: const Key('auth_password'),
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: _register ? null : (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.passwordLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_register)
          TextField(
            key: const Key('auth_password_confirm'),
            controller: _passwordConfirm,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.confirmPasswordLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_register ? l10n.registerAction : l10n.signInAction),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _signInWithGoogle,
          icon: const Icon(Icons.login),
          label: Text(l10n.googleSignInAction),
        ),
        if (!_register)
          TextButton(
            onPressed: _busy ? null : _resetPassword,
            child: Text(l10n.forgotPasswordAction),
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _register = !_register;
                  _error = null;
                }),
          child: Text(_register ? l10n.toggleToSignIn : l10n.toggleToRegister),
        ),
      ],
    );
  }
}

/// Single-field dialog asking for the address to send a password reset to. Owns
/// its controller (a StatefulWidget) so it survives the close animation.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initial});

  final String initial;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.resetPasswordTitle),
      content: TextField(
        key: const Key('reset_email'),
        controller: _controller,
        keyboardType: TextInputType.emailAddress,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.emailLabel,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l10n.sendAction),
        ),
      ],
    );
  }
}
