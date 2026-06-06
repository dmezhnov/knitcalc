import 'package:flutter/widgets.dart';

/// Human-readable language names shown in the language picker, keyed by locale
/// language code and written in the language itself (endonyms).
///
/// Dart has no built-in endonym database, so this is the one place to extend
/// when adding a new locale: drop an `app_<code>.arb` in lib/l10n and add its
/// name here. Locales missing from the map fall back to their language code.
const Map<String, String> _languageNames = {'ru': 'Русский', 'en': 'English'};

/// The display name for [locale]'s language, or its language code as a fallback.
String languageName(Locale locale) =>
    _languageNames[locale.languageCode] ?? locale.languageCode.toUpperCase();
