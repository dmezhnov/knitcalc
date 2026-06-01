import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knitcalc/main.dart';

String? getOutputValue(WidgetTester tester, String key) {
  final List<Text> texts = tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .toList();

  return texts.last.data;
}

void main() {
  testWidgets('calculates rectangular scarf', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Прямоугольный шарф'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Прямоугольный шарф').last);
    await tester.pumpAndSettle();

    expect(find.text('Петель в см'), findsOneWidget);

    final Finder stitchesEl = find.byKey(const Key('stitches'));
    final Finder sampleWidthCmEl = find.byKey(const Key('sampleWidthCm'));
    final Finder rowsEl = find.byKey(const Key('rows'));
    final Finder sampleLengthCmEl = find.byKey(const Key('sampleLengthCm'));
    final Finder targetWidthCmEl = find.byKey(const Key('targetWidthCm'));
    final Finder targetLengthCmEl = find.byKey(const Key('targetLengthCm'));
    final Finder sampleWidthStitchesEl = find.byKey(
      const Key('sampleWidthStitches'),
    );
    final Finder sampleThreadLengthCmEl = find.byKey(
      const Key('sampleThreadLengthCm'),
    );

    await tester.enterText(stitchesEl, '15');
    await tester.enterText(sampleWidthCmEl, '10');
    await tester.enterText(rowsEl, '6');
    await tester.enterText(sampleLengthCmEl, '3.5');
    await tester.enterText(targetWidthCmEl, '50');
    await tester.enterText(targetLengthCmEl, '50');
    await tester.enterText(sampleWidthStitchesEl, '20');
    await tester.enterText(sampleThreadLengthCmEl, '25');
    await tester.pumpAndSettle();

    expect(getOutputValue(tester, 'stitchesPerCm'), '1.5');
    expect(getOutputValue(tester, 'rowsPerCm'), '1.71');
    expect(getOutputValue(tester, 'targetStitches'), '75');
    expect(getOutputValue(tester, 'targetRows'), '85.71');
    expect(getOutputValue(tester, 'targetThreadLength'), '18.75');
  });

  testWidgets('calculates triangular shawl', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Прямоугольный шарф'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Треугольный палантин').last);
    await tester.pumpAndSettle();

    expect(find.text('Ширина в начале (см)'), findsOneWidget);

    final Finder stitchesEl = find.byKey(const Key('stitches'));
    final Finder sampleWidthCmEl = find.byKey(const Key('sampleWidthCm'));
    final Finder rowsEl = find.byKey(const Key('rows'));
    final Finder sampleLengthCmEl = find.byKey(const Key('sampleLengthCm'));
    final Finder startWidthCmEl = find.byKey(const Key('startWidthCm'));
    final Finder endWidthCmEl = find.byKey(const Key('endWidthCm'));
    final Finder targetLengthCmEl = find.byKey(const Key('targetLengthCm'));

    await tester.enterText(stitchesEl, '15');
    await tester.enterText(sampleWidthCmEl, '10');
    await tester.enterText(rowsEl, '6');
    await tester.enterText(sampleLengthCmEl, '3');
    await tester.enterText(startWidthCmEl, '40');
    await tester.enterText(endWidthCmEl, '20');
    await tester.enterText(targetLengthCmEl, '45');
    await tester.pumpAndSettle();

    expect(getOutputValue(tester, 'stitchesPerCm'), '1.5');
    expect(getOutputValue(tester, 'rowsPerCm'), '2');
    expect(getOutputValue(tester, 'startWidthStitches'), '60');
    expect(getOutputValue(tester, 'endWidthStitches'), '30');
    expect(getOutputValue(tester, 'targetRows'), '90');
    expect(getOutputValue(tester, 'changeCount'), '15');
    expect(getOutputValue(tester, 'changeRate'), '6');
  });
}
