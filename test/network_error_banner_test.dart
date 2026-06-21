import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/l10n/locale_scope.dart';
import 'package:knitcalc/network_error_banner.dart';

void main() {
  testWidgets('network error banner follows a runtime language switch', (
    tester,
  ) async {
    final locale = LocaleController(const Locale('ru'));
    addTearDown(locale.dispose);

    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, _) => MaterialApp(
            locale: value,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showNetworkErrorBanner(context, onRetry: () {}),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Shown in Russian (the default locale).
    expect(
      find.text(
        'Нет подключения к сети. Не удалось синхронизировать или проверить обновления.',
      ),
      findsOneWidget,
    );

    // Switch to English at runtime: the banner already on screen must re-localize.
    locale.value = const Locale('en');
    await tester.pumpAndSettle();

    expect(
      find.text('No network connection. Could not sync or check for updates.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Нет подключения к сети. Не удалось синхронизировать или проверить обновления.',
      ),
      findsNothing,
    );
  });
}
