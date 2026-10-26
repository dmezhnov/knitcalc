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

    test('names the gauge fields first in every product that uses it', () {
      for (final product in products) {
        final json =
            jsonDecode(
                  File(
                    '$productsDirectory/${product.id}.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        if (!((json['include'] ?? const []) as List<Object?>).contains(
          'gauge',
        )) {
          continue;
        }
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

  group('evenly spaced increases and decreases', () {
    test('splits a flat row the way the worked example does', () {
      // Modern Daily Knitting, "increase 41 stitches evenly across 197": the
      // flat-row answer (k4, m1) 12 times, (k5, m1) 29 times, k4 is 29
      // segments of 5 and 13 of 4, the last one without an increase.
      final outputs = outputsOf('even_spacing', {
        'fromStitches': 197,
        'toStitches': 238,
      });

      expect(outputs['changeCount']!.value, 41);
      expect(outputs['changeCount']!.label(ru), 'Прибавок');
      expect(outputs['changeCount']!.highlight, isFalse);
      expect(outputs['flatLargeSegments']!.value, 29);
      expect(
        outputs['flatLargeSegments']!.label(ru),
        'В ряду: отрезков по 5 петель',
      );
      expect(outputs['flatSmallSegments']!.value, 13);
      expect(
        outputs['flatSmallSegments']!.label(ru),
        'В ряду: отрезков по 4 петли',
      );
      // In the round every segment ends in an increase: 41 segments.
      expect(outputs['roundLargeSegments']!.value, 33);
      expect(outputs['roundSmallSegments']!.value, 8);
      expect(
        outputs['roundSmallSegments']!.label(en),
        'In the round: segments of 4 stitches',
      );
    });

    test('counts the k2tog into each segment when decreasing', () {
      final outputs = outputsOf('even_spacing', {
        'fromStitches': 100,
        'toStitches': 88,
      });

      expect(outputs['changeCount']!.value, 12);
      expect(outputs['changeCount']!.label(en), 'Decreases');
      // Flat: 13 segments, 9 of 8 and 4 of 7; round: 12, 4 of 9 and 8 of 8.
      expect(outputs['flatLargeSegments']!.value, 9);
      expect(outputs['flatSmallSegments']!.value, 4);
      expect(outputs['roundLargeSegments']!.value, 4);
      expect(outputs['roundSmallSegments']!.value, 8);
    });

    test('uses the singular for one-stitch segments', () {
      final outputs = outputsOf('even_spacing', {
        'fromStitches': 3,
        'toStitches': 5,
      });

      expect(outputs['roundSmallSegments']!.value, 1);
      expect(
        outputs['roundSmallSegments']!.label(ru),
        'По кругу: отрезков по 1 петле',
      );
      expect(
        outputs['roundSmallSegments']!.label(en),
        'In the round: segments of 1 stitch',
      );
    });

    test('flags more decreases than the stitches can take', () {
      // Six k2tog need twelve stitches.
      final outputs = outputsOf('even_spacing', {
        'fromStitches': 10,
        'toStitches': 4,
      });

      expect(outputs['changeCount']!.value, 6);
      expect(outputs['changeCount']!.highlight, isTrue);
      expect(outputs.keys, ['changeCount']);
    });

    test('shows no segments when nothing changes', () {
      final outputs = outputsOf('even_spacing', {
        'fromStitches': 40,
        'toStitches': 40,
      });

      expect(outputs['changeCount']!.value, 0);
      // An empty form reads "0 increases", not "0 decreases".
      expect(outputs['changeCount']!.label(ru), 'Прибавок');
      expect(outputs['changeCount']!.highlight, isFalse);
      expect(outputs.keys, ['changeCount']);
    });
  });

  group('hat', () {
    // 2.2 stitches and 3 rows per cm.
    const gauge = {
      'stitches': 22.0,
      'sampleWidthCm': 10.0,
      'rows': 30.0,
      'sampleLengthCm': 10.0,
    };

    test('casts on a multiple of 8 and leaves room for the crown', () {
      final outputs = outputsOf('hat', {
        ...gauge,
        'headCircumferenceCm': 56,
        'stretchPercent': 10,
        'hatHeightCm': 21,
      });

      // 56 cm less 10% is 110.88 stitches, the nearest multiple of 8 is 112.
      expect(outputs['castOn']!.value, 112);
      expect(outputs['hatCircumferenceCm']!.value, closeTo(50.91, 0.01));
      // 8 stitches off every other round, from 112 down to 8.
      expect(outputs['crownDecreaseRounds']!.value, 13);
      expect(outputs['crownRounds']!.value, 26);
      expect(outputs['crownHeightCm']!.value, closeTo(8.67, 0.01));
      expect(outputs['straightRounds']!.value, 63 - 26);
      expect(outputs['straightRounds']!.highlight, isFalse);
      expect(outputs['finalStitches']!.value, 8);
    });

    test('flags a hat shorter than its crown', () {
      final outputs = outputsOf('hat', {
        ...gauge,
        'headCircumferenceCm': 56,
        'stretchPercent': 10,
        'hatHeightCm': 5,
      });

      expect(outputs['straightRounds']!.value, 15 - 26);
      expect(outputs['straightRounds']!.highlight, isTrue);
    });
  });

  group('socks', () {
    // 3.2 stitches and 4 rows per cm.
    const gauge = {
      'stitches': 32.0,
      'sampleWidthCm': 10.0,
      'rows': 40.0,
      'sampleLengthCm': 10.0,
    };

    test('builds the 64-stitch sock of the Universal Sock Pattern', () {
      final outputs = outputsOf('socks', {
        ...gauge,
        'footCircumferenceCm': 22.2,
        'stretchPercent': 10,
        'legLengthCm': 15,
        'footLengthCm': 24,
      });

      expect(outputs['castOn']!.value, 64);
      expect(outputs['legRounds']!.value, 60);
      // The pattern's 64-stitch sock: a 32-stitch flap of 32 rows and 16
      // stitches picked up along each side.
      expect(outputs['heelStitches']!.value, 32);
      expect(outputs['gussetPickUp']!.value, 16);
      // The flap in thirds: 10 + 12 + 10; the middle 12 stay after the turn.
      expect(outputs['heelSide']!.value, 10);
      expect(outputs['heelMiddle']!.value, 12);
      expect(outputs['gussetDecreaseRounds']!.value, 6);
      // 8 rounds every other round to 32 stitches, 6 more every round to 8:
      // 22 rounds, 5.5 cm — the pattern says to start the toe 2 in (5.1 cm)
      // short of the foot length.
      expect(outputs['toeHalfDecreaseRounds']!.value, 8);
      expect(outputs['toeEveryRoundDecreases']!.value, 6);
      expect(outputs['toeFinalStitches']!.value, 8);
      expect(outputs['toeLengthCm']!.value, 5.5);
      expect(outputs['footBeforeToeCm']!.value, 18.5);
      expect(outputs['footBeforeToeCm']!.highlight, isFalse);
    });

    test('brings the gusset back to the cast-on and the toe down to 8', () {
      // One stitch per cm, so the circumference is the cast-on.
      for (var castOn = 16; castOn <= 120; castOn += 4) {
        final outputs = outputsOf('socks', {
          'stitches': 10,
          'sampleWidthCm': 10,
          'rows': 10,
          'sampleLengthCm': 10,
          'footCircumferenceCm': castOn.toDouble(),
          'footLengthCm': 25,
        });
        final heel = outputs['heelStitches']!.value!;
        final afterPickUp =
            outputs['heelMiddle']!.value! +
            2 * outputs['gussetPickUp']!.value! +
            castOn / 2;

        expect(outputs['castOn']!.value, castOn);
        expect(
          2 * outputs['heelSide']!.value! + outputs['heelMiddle']!.value!,
          heel,
        );
        expect(
          afterPickUp - 2 * outputs['gussetDecreaseRounds']!.value!,
          castOn,
          reason: 'cast-on $castOn',
        );
        expect(
          outputs['toeFinalStitches']!.value,
          8,
          reason: 'cast-on $castOn',
        );
      }
    });
  });

  group('mittens', () {
    test('sizes the hand, the thumb gusset and the top', () {
      final outputs = outputsOf('mittens', {
        'stitches': 20,
        'sampleWidthCm': 10,
        'rows': 28,
        'sampleLengthCm': 10,
        'handCircumferenceCm': 19,
        'easeCm': 1.5,
        'handLengthCm': 18,
      });

      // 20.5 cm at 2 stitches per cm is 41, the nearest multiple of 4 is 40.
      expect(outputs['castOn']!.value, 40);
      // About a third of the hand goes to the thumb.
      expect(outputs['thumbStitches']!.value, 14);
      expect(outputs['thumbIncreaseRounds']!.value, 7);
      expect(outputs['thumbGussetRounds']!.value, 21);
      expect(outputs['topHalfDecreaseRounds']!.value, 5);
      expect(outputs['topEveryRoundDecreases']!.value, 3);
      expect(outputs['topFinalStitches']!.value, 8);
      // 18 cm is 50 rounds, 13 of them for the top.
      expect(outputs['roundsBeforeTop']!.value, 37);
      expect(outputs['roundsBeforeTop']!.highlight, isFalse);
    });
  });

  group('top-down raglan', () {
    // Knitting Fool's metric raglan default: 22 stitches and 25 rows per
    // 10 cm, a 100 cm chest with its "comfortable" 10% of ease. It, too,
    // ends with 121 stitches each for the front and the back, and casts on
    // 97, its 40% of the body.
    const inputs = {
      'stitches': 22.0,
      'sampleWidthCm': 10.0,
      'rows': 25.0,
      'sampleLengthCm': 10.0,
      'finishedChestCm': 110.0,
    };

    test('splits the neck and fits the increases into the yoke', () {
      final outputs = outputsOf('raglan_top_down', {
        ...inputs,
        'yokeDepthCm': 20,
      });

      expect(outputs['bodyStitches']!.value, 242);
      expect(outputs['neckStitches']!.value, 96);
      expect(outputs['bodyStart']!.value, 32);
      expect(outputs['sleeveStart']!.value, 16);
      expect(outputs['yokeRounds']!.value, 50);
      // The sleeve stops at its upper arm (33%) less the underarm (8%):
      // 80 - 19 = 61, reached as closely as 2 a round allow.
      expect(outputs['raglanRounds']!.value, 22);
      expect(outputs['sleeveAtSplit']!.value, 60);
      expect(outputs['bodyOnlyRounds']!.value, 13);
      expect(outputs['bodyAtSplit']!.value, 102);
      expect(outputs['underarmCastOn']!.value, 19);
      expect(outputs['sleeveStitches']!.value, 79);
    });

    test('casts the shortfall of a shallow yoke on under the arm', () {
      final outputs = outputsOf('raglan_top_down', {
        ...inputs,
        'yokeDepthCm': 8,
      });

      // 20 rounds: 10 raglan rounds and 10 body rounds between them.
      expect(outputs['raglanRounds']!.value, 10);
      expect(outputs['bodyOnlyRounds']!.value, 10);
      expect(outputs['bodyAtSplit']!.value, 72);
      expect(outputs['underarmCastOn']!.value, 49);
      expect(
        2 *
            (outputs['bodyAtSplit']!.value! +
                outputs['underarmCastOn']!.value!),
        242,
      );
    });
  });

  group('yarn by swatch weight', () {
    const inputs = {
      'swatchWeightG': 5.0,
      'sampleWidthCm': 10.0,
      'sampleLengthCm': 10.0,
      'pieceWidthCm': 50.0,
      'pieceLengthCm': 150.0,
      'reservePercent': 10.0,
      'skeinWeightG': 100.0,
      'skeinLengthM': 250.0,
    };

    test('scales the swatch weight to the item and rounds skeins up', () {
      final outputs = outputsOf('yarn_by_weight', inputs);

      // 0.05 g per cm² over 7500 cm².
      expect(outputs['itemWeightG']!.value, closeTo(375, 1e-9));
      expect(outputs['totalWeightG']!.value, closeTo(412.5, 1e-9));
      expect(outputs['totalLengthM']!.value, closeTo(1031.25, 1e-9));
      expect(outputs['skeins']!.value, 5);
    });

    test('multiplies by the piece count', () {
      final outputs = outputsOf('yarn_by_weight', {...inputs, 'pieceCount': 2});

      expect(outputs['itemWeightG']!.value, closeTo(750, 1e-9));
      expect(outputs['skeins']!.value, 9);
    });

    test('leaves skeins and metres blank without the skein', () {
      final outputs = outputsOf('yarn_by_weight', {
        ...inputs,
        'skeinWeightG': null,
        'skeinLengthM': null,
      });

      expect(outputs['totalWeightG']!.value, closeTo(412.5, 1e-9));
      expect(outputs['totalLengthM']!.value, isNull);
      expect(outputs['skeins']!.value, isNull);
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
