import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/main.dart';

/// Launches the app. With no saved projects the calculator opens automatically.
Future<void> openCalculator(WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('switches every label between Russian and English', (
    tester,
  ) async {
    await openCalculator(tester);

    // Defaults to Russian.
    expect(find.text('Вид изделия'), findsOneWidget);
    expect(find.text('Прямоугольный шарф'), findsWidgets);
    expect(find.text('Количество петель'), findsOneWidget);

    // Open the language menu and pick English.
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Now English, no Russian left.
    expect(find.text('Item type'), findsOneWidget);
    expect(find.text('Rectangular scarf'), findsWidgets);
    expect(find.text('Stitch count'), findsOneWidget);
    expect(find.text('Вид изделия'), findsNothing);

    // Picking Russian again restores it.
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Вид изделия'), findsOneWidget);
    expect(find.text('Item type'), findsNothing);
  });

  testWidgets('preserves entered values across a language switch', (
    tester,
  ) async {
    await openCalculator(tester);

    await tester.enterText(find.byKey(const Key('stitches')), '15');
    await tester.enterText(find.byKey(const Key('sampleWidthCm')), '10');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // The field controllers survive the rebuild, so the gauge still computes.
    expect(find.text('Stitches per cm'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });
}
