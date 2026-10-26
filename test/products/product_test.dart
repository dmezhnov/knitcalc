import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/products/products.dart';

final AppLocalizations ru = lookupAppLocalizations(const Locale('ru'));
final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

/// A minimal valid product with [overrides] merged over it, so each error
/// case below changes exactly one thing.
Map<String, Object?> productJson([Map<String, Object?> overrides = const {}]) =>
    {
      'name': {'ru': 'Изделие', 'en': 'Item'},
      'inputs': [
        {
          'key': 'widthCm',
          'label': {'ru': 'Ширина', 'en': 'Width'},
        },
      ],
      'values': {'doubled': 'widthCm * 2'},
      'outputs': [
        {
          'key': 'doubled',
          'label': {'ru': 'Вдвое', 'en': 'Doubled'},
          'value': 'doubled',
        },
      ],
      ...overrides,
    };

Matcher throwsFormatMentioning(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

Map<String, ProductOutput> outputsOf(String id, Map<String, double?> values) =>
    {
      for (final output in productById(id).computeOutputs(values))
        output.key: output,
    };

void main() {
  group('the shipped catalog', () {
    final directory = Directory(productsDirectory);
    final index =
        (jsonDecode(File('$productsDirectory/index.json').readAsStringSync())
                as Map<String, Object?>)['products']!
            as List<Object?>;

    test('lists every product file in the index, in index order', () {
      final files = directory
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.json') && name != 'index.json')
          .map((name) => name.substring(0, name.length - '.json'.length))
          .toSet();

      expect(files, index.toSet());
      expect(products.map((product) => product.id), index);
    });

    test('uses every shared part', () {
      final partFiles = Directory('$productsDirectory/parts')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last.replaceAll('.json', ''))
          .toSet();
      final included = {
        for (final id in index)
          ...((jsonDecode(
                        File('$productsDirectory/$id.json').readAsStringSync(),
                      )
                      as Map<String, Object?>)['include'] ??
                  const [])
              as List<Object?>,
      };

      expect(included, partFiles);
    });

    test('computes and labels every product in every language', () {
      for (final product in products) {
        for (final fill in [0.0, 7.0, null]) {
          final values = {for (final input in product.inputs) input.key: fill};
          for (final l10n in [ru, en]) {
            expect(product.name(l10n), isNotEmpty);
            for (final input in product.inputs) {
              expect(input.label(l10n), isNotEmpty);
            }
            for (final output in product.computeOutputs(values)) {
              expect(output.label(l10n), isNotEmpty, reason: output.key);
            }
          }
        }
      }
    });

    // The app reads the catalog through the asset bundle, which only holds
    // what pubspec.yaml declares; the rest of this file reads it from disk.
    testWidgets('ships every product file as an asset', (tester) async {
      final bundled = await tester.runAsync(
        () => readProductCatalog(rootBundle.loadString),
      );

      expect(bundled!.map((product) => product.id), index);
    });

    test('names the gauge fields first in every product', () {
      for (final product in products) {
        expect(product.inputs.take(4).map((input) => input.key), [
          'stitches',
          'sampleWidthCm',
          'rows',
          'sampleLengthCm',
        ]);
      }
    });
  });

  group('triangular shawl', () {
    // 1.5 stitches and 2 rows per cm.
    const gauge = {
      'stitches': 15.0,
      'sampleWidthCm': 10.0,
      'rows': 6.0,
      'sampleLengthCm': 3.0,
    };

    test('switches its labels to increases when the shawl widens', () {
      final outputs = outputsOf('triangular_shawl', {
        ...gauge,
        'startWidthCm': 20,
        'endWidthCm': 40,
        'targetLengthCm': 45,
      });

      expect(outputs['changeCount']!.value, 15);
      expect(outputs['changeCount']!.label(ru), 'Прибавок с каждой стороны');
      expect(outputs['changeRate']!.label(en), 'Increase rate');
      expect(outputs['changeRate']!.value, 6);
      expect(outputs['changeRate']!.highlight, isFalse);
    });

    test('highlights a rate that is not a whole number of rows', () {
      final outputs = outputsOf('triangular_shawl', {
        ...gauge,
        'startWidthCm': 40,
        'endWidthCm': 20,
        'targetLengthCm': 50,
      });

      expect(outputs['changeRate']!.label(ru), 'Темп убавок');
      expect(outputs['changeRate']!.value, closeTo(6.67, 0.01));
      expect(outputs['changeRate']!.highlight, isTrue);
    });

    test('has no rate when the width does not change', () {
      final outputs = outputsOf('triangular_shawl', {
        ...gauge,
        'startWidthCm': 30,
        'endWidthCm': 30,
        'targetLengthCm': 50,
      });

      expect(outputs['changeCount']!.value, 0);
      expect(outputs['changeRate']!.value, isNull);
      expect(outputs['changeRate']!.highlight, isFalse);
    });
  });

  group('shoulder slope', () {
    const gauge = {
      'stitches': 16.0,
      'sampleWidthCm': 10.0,
      'rows': 20.0,
      'sampleLengthCm': 10.0,
    };

    test('words the stitch groups with the plural rules of each language', () {
      final outputs = outputsOf('shoulder_slope', {
        ...gauge,
        'shoulderWidthCm': 20,
        'shoulderHeightCm': 6.5,
      });

      expect(
        outputs['largeStepRows']!.label(ru),
        'Рядов с убавкой по 5 петель',
      );
      expect(outputs['smallStepRows']!.label(ru), 'Рядов с убавкой по 4 петли');
      expect(
        outputs['smallStepRows']!.label(en),
        'Rows decreasing by 4 stitches',
      );
    });

    test('uses the singular for a one-stitch group', () {
      // 3 stitches over 2 decrease rows: one row of 2 and one row of 1.
      final outputs = outputsOf('shoulder_slope', {
        ...gauge,
        'shoulderWidthCm': 1.875,
        'shoulderHeightCm': 2,
      });

      expect(outputs['smallStepRows']!.value, 1);
      expect(outputs['smallStepRows']!.label(ru), 'Рядов с убавкой по 1 петле');
      expect(
        outputs['smallStepRows']!.label(en),
        'Rows decreasing by 1 stitch',
      );
    });

    test('has no decrease rows and no groups for a flat shoulder', () {
      final outputs = outputsOf('shoulder_slope', {
        ...gauge,
        'shoulderWidthCm': 20,
        'shoulderHeightCm': 0,
      });

      expect(outputs['decreaseRows']!.value, isNull);
      expect(outputs.containsKey('largeStepRows'), isFalse);
      expect(outputs.containsKey('smallStepRows'), isFalse);
    });
  });

  group('Product.fromJson', () {
    test('reads a valid product', () {
      final product = Product.fromJson('item', productJson());
      final outputs = product.computeOutputs({'widthCm': 3});

      expect(product.id, 'item');
      expect(product.name(en), 'Item');
      expect(outputs.single.value, 6);
      expect(outputs.single.label(ru), 'Вдвое');
    });

    test('puts included parts before the product, in order', () {
      final product = Product.fromJson(
        'item',
        productJson({
          'include': ['first'],
        }),
        parts: {
          'first': {
            'inputs': [
              {
                'key': 'base',
                'label': {'ru': 'База', 'en': 'Base'},
              },
            ],
            'values': {'baseTwice': 'base * 2'},
          },
        },
      );

      expect(product.inputs.map((input) => input.key), ['base', 'widthCm']);
    });

    test('rejects an unknown key, naming where it is', () {
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'outputs': [
              {
                'key': 'doubled',
                'label': {'ru': 'Вдвое', 'en': 'Doubled'},
                'value': 'doubled',
                'hightlight': 'true',
              },
            ],
          }),
        ),
        throwsFormatMentioning(
          'Product "item", outputs[0]: unknown key(s) '
          'hightlight',
        ),
      );
    });

    test('rejects a text missing a language', () {
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'name': {'ru': 'Изделие'},
          }),
        ),
        throwsFormatMentioning('name.en: missing translation'),
      );
    });

    test('rejects a formula reading an undefined or later value', () {
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'values': {'a': 'b + 1', 'b': 'widthCm'},
          }),
        ),
        throwsFormatMentioning('values.a: unknown variable(s) b'),
      );
    });

    test('rejects a formula that does not parse', () {
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'values': {'a': 'widthCm *'},
          }),
        ),
        throwsFormatMentioning('values.a: Unexpected end of formula'),
      );
    });

    test('rejects a name defined twice or a reserved word', () {
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'values': {'widthCm': '1'},
          }),
        ),
        throwsFormatMentioning('"widthCm" is already defined'),
      );
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'values': {'null': '1'},
          }),
        ),
        throwsFormatMentioning('"null" is not a valid name'),
      );
    });

    test('rejects an unknown part', () {
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'include': ['gauge'],
          }),
        ),
        throwsFormatMentioning('include[0]: unknown part "gauge"'),
      );
    });

    test('rejects a plural without the "other" form', () {
      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'outputs': [
              {
                'key': 'doubled',
                'label': {
                  'plural': 'doubled',
                  'ru': {'one': '{count} петля', 'other': '{count} петель'},
                  'en': {'one': '{count} stitch'},
                },
                'value': 'doubled',
              },
            ],
          }),
        ),
        throwsFormatMentioning('outputs[0].label.en: a plural needs'),
      );
    });

    test('rejects a duplicate output key', () {
      final output = {
        'key': 'doubled',
        'label': {'ru': 'Вдвое', 'en': 'Doubled'},
        'value': 'doubled',
      };

      expect(
        () => Product.fromJson(
          'item',
          productJson({
            'outputs': [output, output],
          }),
        ),
        throwsFormatMentioning('duplicate output key "doubled"'),
      );
    });
  });
}
