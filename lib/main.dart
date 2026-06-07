import 'package:flutter/material.dart';
import 'package:knitcalc/firebase/auth_scope.dart';
import 'package:knitcalc/firebase/auth_service.dart';
import 'package:knitcalc/home.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/l10n/locale_scope.dart';
import 'package:knitcalc/verify_email_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// Active locale, switchable at runtime via [LocaleScope]. Defaults to
  /// Russian; the language toggle in [Home] flips it to English.
  final LocaleController _locale = LocaleController(const Locale('ru'));

  /// Holds the cloud sign-in session; restored from disk on startup.
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _auth.init();
  }

  @override
  void dispose() {
    _locale.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      service: _auth,
      child: LocaleScope(
        controller: _locale,
        child: ValueListenableBuilder<Locale>(
          valueListenable: _locale,
          builder: (context, locale, _) {
            return MaterialApp(
              title: 'KnitCalc',
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(
                colorScheme: .fromSeed(seedColor: Colors.deepPurple),
              ),
              home: const AppRoot(),
            );
          },
        ),
      ),
    );
  }
}

/// Chooses the root screen from the sign-in state: the verification gate while a
/// signed-in account is unconfirmed, otherwise the app itself. Rebuilds via
/// [AuthScope] when the session changes.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    if (AuthScope.of(context).needsVerification) {
      return const VerifyEmailScreen();
    }

    return const Home();
  }
}
