import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knitcalc/main.dart';

void main() {
  testWidgets('calculates rectangular scarf values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Прямоугольный шарф'), findsOneWidget);
    expect(find.text('Петель в см'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Количество петель'),
      '20',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Количество рядов'),
      '30',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ширина образца (см)'),
      '10',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Длина образца (см)'),
      '15',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ширина образца (петель)'),
      '20',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Желаемая ширина (см)'),
      '50',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Желаемая длина (см)'),
      '120',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Длина нити образца (см)'),
      '400',
    );
    await tester.pumpAndSettle();

    expect(find.text('100'), findsOneWidget);
    expect(find.text('240'), findsOneWidget);
    expect(find.text('400'), findsWidgets);
  });
}
