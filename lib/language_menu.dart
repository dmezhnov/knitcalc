import 'package:flutter/material.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/l10n/language.dart';
import 'package:knitcalc/l10n/locale_scope.dart';

/// App-bar action that switches the active locale at runtime via [LocaleScope].
/// Shared by every screen so the language toggle is always reachable.
class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = LocaleScope.of(context);

    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.language),
      tooltip: languageName(controller.value),
      initialValue: controller.value,
      onSelected: (locale) => controller.value = locale,
      itemBuilder: (context) => [
        for (final locale in AppLocalizations.supportedLocales)
          CheckedPopupMenuItem(
            value: locale,
            checked: locale.languageCode == controller.value.languageCode,
            child: Text(languageName(locale)),
          ),
      ],
    );
  }
}
