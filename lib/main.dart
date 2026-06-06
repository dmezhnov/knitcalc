import 'package:flutter/material.dart';
import 'package:knitcalc/home.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/l10n/locale_scope.dart';

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

  @override
  void dispose() {
    _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
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
            home: const Home(),
          );
        },
      ),
    );
  }
}
