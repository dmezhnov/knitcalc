import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/ui/update_banner.dart';
import 'package:knitcalc/update/update_info.dart';

void main() {
  testWidgets('a newer update banner replaces the one already shown', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    UpdateInfo info(String label, AppVersion version) => UpdateInfo(
      latestVersion: version,
      versionLabel: label,
      action: UpdateAction.inApp,
    );

    showUpdateBanner(
      ctx,
      info: info('1.8.45+68', const AppVersion(1, 8, 45, 68)),
      onUpdate: () {},
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1.8.45+68'), findsOneWidget);

    // A newer release arrives while the banner is up: it must supersede the old
    // one, not queue behind it.
    showUpdateBanner(
      ctx,
      info: info('1.8.46+69', const AppVersion(1, 8, 46, 69)),
      onUpdate: () {},
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1.8.46+69'), findsOneWidget);
    expect(find.textContaining('1.8.45+68'), findsNothing);
  });
}
