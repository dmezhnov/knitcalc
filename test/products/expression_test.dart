import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/products/expression.dart';

double? eval(String source, [Map<String, double?> scope = const {}]) =>
    Expression.parse(source).evaluate(scope);

void main() {
  group('arithmetic', () {
    test('follows the usual precedence and left associativity', () {
      expect(eval('1 + 2 * 3'), 7);
      expect(eval('(1 + 2) * 3'), 9);
      expect(eval('10 - 4 - 3'), 3);
      expect(eval('12 / 2 / 3'), 2);
      expect(eval('2 * 7 % 4'), 2);
      expect(eval('-2 * 3'), -6);
      expect(eval('- -2'), 2);
      expect(eval('0.5 + 0.25'), 0.75);
    });

    test('divides and takes a remainder by zero as zero', () {
      expect(eval('5 / 0'), 0);
      expect(eval('5 % 0'), 0);
      expect(eval('32 % 7'), 4);
    });
  });

  group('null', () {
    test('stays null through arithmetic and functions', () {
      expect(eval('null + 1'), isNull);
      expect(eval('-null'), isNull);
      expect(eval('round(null)'), isNull);
      expect(eval('max(1, null)'), isNull);
    });

    test('fails an ordering but compares equal only to itself', () {
      expect(eval('null > 0'), 0);
      expect(eval('null <= 0'), 0);
      expect(eval('null == null'), 1);
      expect(eval('null != 0'), 1);
      expect(eval('null == 0'), 0);
    });

    test('is false in a condition', () {
      expect(eval('null ? 1 : 2'), 2);
      expect(eval('!null'), 1);
    });
  });

  group('logic', () {
    test('compares', () {
      expect(eval('2 <= 2'), 1);
      expect(eval('2 >= 3'), 0);
      expect(eval('3 < 2'), 0);
      expect(eval('3 > 2'), 1);
      expect(eval('1 + 1 == 2'), 1);
    });

    test('combines conditions with the usual precedence', () {
      expect(eval('1 && 0'), 0);
      expect(eval('1 || 0'), 1);
      expect(eval('!0'), 1);
      expect(eval('0 || 1 && 0'), 0);
      expect(eval('true && !false'), 1);
    });

    test('short-circuits, so a guard keeps the right side unevaluated', () {
      // `missing` is not in the scope: reading it would throw.
      expect(eval('0 && missing'), 0);
      expect(eval('1 || missing'), 1);
      expect(eval('1 ? 2 : missing'), 2);
    });

    test('nests conditionals to the right', () {
      expect(eval('0 ? 1 : 0 ? 2 : 3'), 3);
      expect(eval('0 ? 1 : 1 ? 2 : 3'), 2);
      expect(eval('1 ? 0 ? 4 : 5 : 6'), 5);
    });
  });

  test('functions round half away from zero, like roundToDouble', () {
    expect(eval('round(2.5)'), 3);
    expect(eval('round(-2.5)'), -3);
    expect(eval('round(0.5)'), 1);
    expect(eval('floor(-1.5)'), -2);
    expect(eval('ceil(1.2)'), 2);
    expect(eval('abs(-3)'), 3);
    expect(eval('min(2, 5)'), 2);
    expect(eval('max(2, 5)'), 5);
  });

  test('reads variables from the scope and reports them', () {
    final formula = Expression.parse('round(stitchesPerCm * widthCm) + 1');

    expect(formula.variables, {'stitchesPerCm', 'widthCm'});
    expect(formula.evaluate({'stitchesPerCm': 1.6, 'widthCm': 20}), 33);
    expect(() => formula.evaluate({'widthCm': 20}), throwsStateError);
  });

  test('rejects a malformed formula with a FormatException', () {
    for (final source in [
      '',
      '1 +',
      '(1',
      '1 2',
      '1 = 2',
      'a & b',
      'foo(1)',
      'round(1, 2)',
      'max(1)',
      '1 ? 2',
    ]) {
      expect(
        () => Expression.parse(source),
        throwsFormatException,
        reason: source,
      );
    }
  });
}
