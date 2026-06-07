import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/main.dart';

/// Current text of the input field registered under [key].
String fieldText(WidgetTester tester, String key) {
  final editable = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(EditableText),
  );

  return tester.widget<EditableText>(editable).controller.text;
}

/// The description text field, located by its floating label.
Finder descriptionField() =>
    find.ancestor(of: find.text('Описание'), matching: find.byType(TextField));

/// Current text of the description field.
String descriptionText(WidgetTester tester) {
  final editable = find.descendant(
    of: descriptionField(),
    matching: find.byType(EditableText),
  );

  return tester.widget<EditableText>(editable).controller.text;
}

/// Opens the calculator, enters a stitch count and width, saves under [name],
/// and returns to the home list. Taps "New" only when the list is shown; on an
/// empty list the calculator is already open (auto-opened at startup).
Future<void> createProject(
  WidgetTester tester, {
  required String name,
  String stitches = '15',
  String width = '10,5',
  String? description,
}) async {
  final newButton = find.text('Новое');
  if (newButton.evaluate().isNotEmpty) {
    await tester.tap(newButton);
    await tester.pumpAndSettle();
  }

  await tester.enterText(find.byKey(const Key('stitches')), stitches);
  await tester.enterText(find.byKey(const Key('sampleWidthCm')), width);
  if (description != null) {
    await tester.enterText(descriptionField(), description);
  }
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Сохранить'));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    name,
  );
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Сохранить'),
    ),
  );
  await tester.pumpAndSettle();

  // Return to the list. In the empty-state (inline) calculator there is no back
  // button — saving repopulates the list automatically; in a pushed calculator
  // we pop back to it.
  final back = find.byType(BackButton);
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows only the calculator when nothing is saved', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The calculator is the whole app: its fields are shown...
    expect(find.text('Вид изделия'), findsOneWidget);
    // ...and there is no way to navigate to an (empty) list.
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('saved project appears in the list and reopens with its values', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await createProject(tester, name: 'Мой шарф');

    // Back on the home list, the project is shown.
    expect(find.text('Мой шарф'), findsOneWidget);

    // Reopening it restores the entered values.
    await tester.tap(find.text('Мой шарф'));
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'stitches'), '15');
    expect(fieldText(tester, 'sampleWidthCm'), '10,5');
  });

  testWidgets('persists a description', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await createProject(
      tester,
      name: 'С описанием',
      description: 'мягкая шерсть',
    );

    await tester.tap(find.text('С описанием'));
    await tester.pumpAndSettle();

    expect(descriptionText(tester), 'мягкая шерсть');
  });

  testWidgets('deletes a saved project from the list', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await createProject(tester, name: 'Удаляемый');

    expect(find.text('Удаляемый'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Удалить'),
      ),
    );
    await tester.pumpAndSettle();

    // The list is now empty, so the app falls back to the calculator.
    expect(find.text('Удаляемый'), findsNothing);
    expect(find.text('Вид изделия'), findsOneWidget);
  });
}
