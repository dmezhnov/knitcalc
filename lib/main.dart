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

/// Forces the hand (click) cursor on the Material button family. Flutter's button
/// default is [WidgetStateMouseCursor.adaptiveClickable], which shows the click
/// cursor only on web and the plain arrow on desktop; we want the hand on every
/// platform so buttons feel clickable on Linux/Windows/macOS too — matching
/// [ListTile]/[InkWell], which already default to the always-on
/// [WidgetStateMouseCursor.clickable].
const ButtonStyle _clickableButtonStyle = ButtonStyle(
  mouseCursor: WidgetStateMouseCursor.clickable,
);

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
                // Give the whole button family the hand cursor on desktop (see
                // _clickableButtonStyle). FAB and popup menus expose the cursor
                // on their own theme objects rather than a ButtonStyle.
                iconButtonTheme: const IconButtonThemeData(
                  style: _clickableButtonStyle,
                ),
                textButtonTheme: const TextButtonThemeData(
                  style: _clickableButtonStyle,
                ),
                filledButtonTheme: const FilledButtonThemeData(
                  style: _clickableButtonStyle,
                ),
                outlinedButtonTheme: const OutlinedButtonThemeData(
                  style: _clickableButtonStyle,
                ),
                elevatedButtonTheme: const ElevatedButtonThemeData(
                  style: _clickableButtonStyle,
                ),
                floatingActionButtonTheme: const FloatingActionButtonThemeData(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                ),
                popupMenuTheme: const PopupMenuThemeData(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                ),
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
