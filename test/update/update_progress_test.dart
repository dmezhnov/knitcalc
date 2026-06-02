import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/ui/update_progress.dart';

Future<void> _pumpDialog(
  WidgetTester tester,
  ValueListenable<double?> progress,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: UpdateProgressDialog(progress: progress)),
    ),
  );
}

void main() {
  group('UpdateProgressDialog', () {
    testWidgets('shows a preparing label while progress is unknown', (
      tester,
    ) async {
      final progress = ValueNotifier<double?>(null);
      addTearDown(progress.dispose);

      await _pumpDialog(tester, progress);

      expect(find.text('Подготовка…'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, isNull);
    });

    testWidgets('renders the rounded percentage as it advances', (
      tester,
    ) async {
      final progress = ValueNotifier<double?>(0.0);
      addTearDown(progress.dispose);

      await _pumpDialog(tester, progress);
      expect(find.text('0%'), findsOneWidget);

      progress.value = 0.426;
      await tester.pump();

      expect(find.text('43%'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(0.426, 1e-9));
    });
  });
}
