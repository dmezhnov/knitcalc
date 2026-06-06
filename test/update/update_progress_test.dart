import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/update/ui/update_progress.dart';
import 'package:knitcalc/update/update_service.dart';

Future<void> _pumpDialog(
  WidgetTester tester,
  ValueListenable<DownloadProgress?> progress,
) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: UpdateProgressDialog(progress: progress)),
    ),
  );
}

void main() {
  group('UpdateProgressDialog', () {
    testWidgets('shows a preparing label while progress is unknown', (
      tester,
    ) async {
      final progress = ValueNotifier<DownloadProgress?>(null);
      addTearDown(progress.dispose);

      await _pumpDialog(tester, progress);

      expect(find.text('Подготовка…'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, isNull);
    });

    testWidgets('renders the rounded percentage and bytes as it advances', (
      tester,
    ) async {
      const total = 12 * 1024 * 1024;
      final progress = ValueNotifier<DownloadProgress?>(
        const DownloadProgress(received: 0, total: total),
      );
      addTearDown(progress.dispose);

      await _pumpDialog(tester, progress);
      expect(find.text('0%'), findsOneWidget);

      progress.value = DownloadProgress(
        received: (total * 0.426).round(),
        total: total,
      );
      await tester.pump();

      expect(find.text('43%'), findsOneWidget);
      // Downloaded-of-total line is shown once a total is known.
      expect(find.textContaining('/ 12 МБ'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(0.426, 1e-3));
    });
  });
}
