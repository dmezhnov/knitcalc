/// Abstractions shared by every product (вид изделия).
///
/// A product is fully described by three things:
///   * which inputs it needs ([Product.inputs]),
///   * which outputs it produces and how they are computed from the inputs
///     ([Product.computeOutputs]),
///   * how it is labelled and identified in the UI ([Product.id],
///     [Product.name]).
///
/// None of that is Dart code: each product is a JSON file under
/// assets/products/ (see lib/products/README.md for the format), and
/// [Product.fromJson] turns it into this class. The UI knows nothing about
/// specific products: it renders [Product.inputs] as fields, feeds the entered
/// values back into [Product.computeOutputs], and renders the result. Adding a
/// new product means adding one JSON file and listing it in the index — no Dart
/// or UI changes required.
///
/// A product's texts live in its own file, one string per supported language,
/// rather than in lib/l10n/*.arb: gen-l10n turns every ARB message into a
/// compiled getter, so a product read at run time could not name its strings
/// there. They still resolve through [LocalizedString], keyed by
/// [AppLocalizations.localeName], so the language switch works as before.
library;

import 'package:intl/intl.dart';
import 'package:knitcalc/l10n/app_localizations.dart';

import 'expression.dart';

/// Resolves a user-facing string for the active locale.
typedef LocalizedString = String Function(AppLocalizations l10n);

/// A single numeric input field of a product.
class ProductInput {
  const ProductInput({
    required this.key,
    required this.label,
    this.hint,
    this.allowDecimal = true,
  });

  /// Stable identifier, also used as the widget [Key], the map key passed to
  /// [Product.computeOutputs] and the variable name in formulas.
  final String key;

  /// Resolves the field label for the active locale.
  final LocalizedString label;

  /// Resolves an optional explanation shown under the field (a typical range,
  /// how to measure), or `null` when the label says everything.
  final LocalizedString? hint;

  /// Whether the field accepts a fractional value.
  final bool allowDecimal;
}

/// A single computed result of a product.
class ProductOutput {
  const ProductOutput({
    required this.key,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  /// Stable identifier, also used as the widget [Key].
  final String key;

  /// Resolves the row label for the active locale. May depend on the inputs
  /// (e.g. decreases vs increases, or a plural form of a computed count).
  final LocalizedString label;

  /// The computed number, or `null` when it cannot be computed. Formatting is a
  /// presentation concern handled by the UI.
  final double? value;

  /// When `true` the UI highlights the row to warn the user about [value]
  /// (e.g. a non-integer change rate).
  final bool highlight;
}

/// The language codes every product text must be written in: one per
/// lib/l10n/app_<code>.arb, so a product can never lag behind the UI.
List<String> get productLanguages => [
  for (final locale in AppLocalizations.supportedLocales) locale.languageCode,
];

/// A kind of knitted item the calculator supports, read from its JSON file.
class Product {
  const Product._({
    required this.id,
    required this.name,
    required this.inputs,
    required List<_NamedFormula> values,
    required List<_OutputSpec> outputs,
  }) : _values = values,
       _outputs = outputs;

  /// Builds a product from its decoded JSON file. [id] comes from the index
  /// rather than the file, and [parts] holds the decoded shared parts the file
  /// may `include` (such as the gauge every product starts from), keyed by
  /// name.
  ///
  /// Everything that can be wrong with the file is reported here, as a
  /// [FormatException] naming the product and the place: a misspelt key, a
  /// missing translation, a formula that does not parse or reads a variable
  /// that is not defined before it.
  factory Product.fromJson(
    String id,
    Object? json, {
    Map<String, Object?> parts = const {},
  }) => _ProductReader(id).read(json, parts);

  /// Stable identifier, used as the dropdown value and stored in saved
  /// projects.
  final String id;

  /// Resolves the product name shown in the dropdown for the active locale.
  final LocalizedString name;

  /// The inputs this product needs, in display order.
  final List<ProductInput> inputs;

  /// Intermediate values, each computed from the inputs and the values before
  /// it, in order.
  final List<_NamedFormula> _values;

  final List<_OutputSpec> _outputs;

  /// Computes the outputs from the entered [values], keyed by [ProductInput.key].
  /// A missing or unparsable field is passed as `null` and counts as `0`, so a
  /// half-filled form shows zeros rather than dashes, as it always has.
  List<ProductOutput> computeOutputs(Map<String, double?> values) {
    final scope = <String, double?>{
      for (final input in inputs) input.key: values[input.key] ?? 0,
    };
    for (final value in _values) {
      scope[value.name] = value.formula.evaluate(scope);
    }

    return [
      for (final output in _outputs)
        if (output.when == null || isTruthy(output.when!.evaluate(scope)))
          ProductOutput(
            key: output.key,
            label: (l10n) => output.label.resolve(_language(l10n), scope),
            value: output.value.evaluate(scope),
            highlight:
                output.highlight != null &&
                isTruthy(output.highlight!.evaluate(scope)),
          ),
    ];
  }
}

/// The language code of the active locale ("en" for "en_US").
String _language(AppLocalizations l10n) => l10n.localeName.split('_').first;

class _NamedFormula {
  const _NamedFormula(this.name, this.formula);

  final String name;
  final Expression formula;
}

class _OutputSpec {
  const _OutputSpec({
    required this.key,
    required this.label,
    required this.value,
    this.highlight,
    this.when,
  });

  final String key;
  final _Text label;
  final Expression value;

  /// Highlights the row when true.
  final Expression? highlight;

  /// Shows the row only when true; `null` always shows it.
  final Expression? when;
}

/// A user-facing text in every product language. Output labels may depend on
/// the computed values, which is why [resolve] takes the scope.
sealed class _Text {
  const _Text();

  String resolve(String language, Map<String, double?> scope);

  /// Variables the text reads, checked like formula variables.
  Set<String> get variables;
}

/// The same text whatever the values: `{"ru": "...", "en": "..."}`.
class _PlainText extends _Text {
  const _PlainText(this.byLanguage);

  final Map<String, String> byLanguage;

  @override
  String resolve(String language, Map<String, double?> scope) =>
      byLanguage[language] ?? byLanguage.values.first;

  @override
  Set<String> get variables => const {};
}

/// One of two texts picked by a condition:
/// `{"if": "<formula>", "then": <text>, "else": <text>}`.
class _ConditionalText extends _Text {
  const _ConditionalText(this.condition, this.then, this.otherwise);

  final Expression condition;
  final _Text then;
  final _Text otherwise;

  @override
  String resolve(String language, Map<String, double?> scope) =>
      (isTruthy(condition.evaluate(scope)) ? then : otherwise).resolve(
        language,
        scope,
      );

  @override
  Set<String> get variables => {
    ...condition.variables,
    ...then.variables,
    ...otherwise.variables,
  };
}

/// A text that agrees with a computed count:
/// `{"plural": "<formula>", "ru": {"one": "...", "few": "...", "other": "..."}}`.
/// `{count}` in a form is replaced with the count, and the form is chosen by
/// the language's CLDR plural rules, as an ICU plural in an ARB file would be.
class _PluralText extends _Text {
  const _PluralText(this.count, this.formsByLanguage);

  final Expression count;
  final Map<String, Map<String, String>> formsByLanguage;

  @override
  String resolve(String language, Map<String, double?> scope) {
    final forms = formsByLanguage[language] ?? formsByLanguage.values.first;
    final value = (count.evaluate(scope) ?? 0).round();
    final form = Intl.pluralLogic(
      value,
      locale: language,
      zero: forms['zero'],
      one: forms['one'],
      two: forms['two'],
      few: forms['few'],
      many: forms['many'],
      other: forms['other']!,
    );

    return form.replaceAll('{count}', '$value');
  }

  @override
  Set<String> get variables => count.variables;
}

/// The plural categories CLDR defines; a plural text may use any of them and
/// must always have `other`.
const Set<String> _pluralForms = {'zero', 'one', 'two', 'few', 'many', 'other'};

final RegExp _identifier = RegExp(r'^[A-Za-z_]\w*$');

/// Words a formula reads as literals, so they cannot name a variable.
const Set<String> _reservedNames = {'null', 'true', 'false'};

/// Reads one product's JSON, collecting the path of whatever is being read so
/// an error says exactly where the file is wrong.
class _ProductReader {
  _ProductReader(this.id);

  final String id;

  Product read(Object? json, Map<String, Object?> parts) {
    final root = _object(json, '');
    _checkKeys(root, const {
      'name',
      'include',
      'inputs',
      'values',
      'outputs',
    }, '');

    // Shared parts come first, in the order listed, then the product's own
    // definitions — so every product opens with the gauge.
    final sections = <(Map<String, Object?>, String)>[];
    for (final (index, name) in _list(
      root['include'] ?? const [],
      'include',
    ).indexed) {
      final partName = _string(name, 'include[$index]');
      if (!parts.containsKey(partName)) {
        _fail('include[$index]', 'unknown part "$partName"');
      }
      final part = _object(parts[partName], 'part $partName');
      _checkKeys(part, const {'inputs', 'values', 'outputs'}, 'part $partName');
      sections.add((part, 'part $partName: '));
    }
    sections.add((root, ''));

    final defined = <String>{};
    final inputs = <ProductInput>[];
    final values = <_NamedFormula>[];
    final outputs = <_OutputSpec>[];
    final outputKeys = <String>{};

    for (final (section, prefix) in sections) {
      for (final (index, item) in _list(
        section['inputs'] ?? const [],
        '${prefix}inputs',
      ).indexed) {
        final input = _input(item, '${prefix}inputs[$index]');
        _define(defined, input.key, '${prefix}inputs[$index]');
        inputs.add(input);
      }
    }
    for (final (section, prefix) in sections) {
      final named = _object(
        section['values'] ?? const <String, Object?>{},
        '${prefix}values',
      );
      for (final MapEntry(key: name, value: source) in named.entries) {
        final where = '${prefix}values.$name';
        final formula = _formula(source, where, defined);
        _define(defined, name, where);
        values.add(_NamedFormula(name, formula));
      }
    }
    for (final (section, prefix) in sections) {
      for (final (index, item) in _list(
        section['outputs'] ?? const [],
        '${prefix}outputs',
      ).indexed) {
        final where = '${prefix}outputs[$index]';
        final output = _output(item, where, defined);
        if (!outputKeys.add(output.key)) {
          _fail(where, 'duplicate output key "${output.key}"');
        }
        outputs.add(output);
      }
    }

    final name = _text(root['name'], 'name', const {});

    return Product._(
      id: id,
      name: (l10n) => name.resolve(_language(l10n), const {}),
      inputs: inputs,
      values: values,
      outputs: outputs,
    );
  }

  ProductInput _input(Object? json, String where) {
    final map = _object(json, where);
    _checkKeys(map, const {'key', 'label', 'hint', 'allowDecimal'}, where);
    final key = _string(map['key'], '$where.key');
    final label = _text(map['label'], '$where.label', const {});
    final hint = map['hint'] == null
        ? null
        : _text(map['hint'], '$where.hint', const {});
    final allowDecimal = map['allowDecimal'] ?? true;
    if (allowDecimal is! bool) {
      _fail('$where.allowDecimal', 'expected true or false');
    }

    return ProductInput(
      key: key,
      label: (l10n) => label.resolve(_language(l10n), const {}),
      hint: hint == null
          ? null
          : (l10n) => hint.resolve(_language(l10n), const {}),
      allowDecimal: allowDecimal,
    );
  }

  _OutputSpec _output(Object? json, String where, Set<String> defined) {
    final map = _object(json, where);
    _checkKeys(map, const {
      'key',
      'label',
      'value',
      'highlight',
      'when',
    }, where);

    return _OutputSpec(
      key: _string(map['key'], '$where.key'),
      label: _text(map['label'], '$where.label', defined),
      value: _formula(map['value'], '$where.value', defined),
      highlight: map['highlight'] == null
          ? null
          : _formula(map['highlight'], '$where.highlight', defined),
      when: map['when'] == null
          ? null
          : _formula(map['when'], '$where.when', defined),
    );
  }

  /// A text in one of the three shapes [_PlainText], [_ConditionalText] and
  /// [_PluralText] describe. [defined] is what a conditional or plural text
  /// may read; inputs and the product name read nothing.
  _Text _text(Object? json, String where, Set<String> defined) {
    final map = _object(json, where);

    if (map.containsKey('if')) {
      _checkKeys(map, const {'if', 'then', 'else'}, where);

      return _ConditionalText(
        _formula(map['if'], '$where.if', defined),
        _text(map['then'], '$where.then', defined),
        _text(map['else'], '$where.else', defined),
      );
    }

    if (map.containsKey('plural')) {
      _checkKeys(map, {'plural', ...productLanguages}, where);
      final count = _formula(map['plural'], '$where.plural', defined);
      final formsByLanguage = <String, Map<String, String>>{};
      for (final language in productLanguages) {
        final formsWhere = '$where.$language';
        if (!map.containsKey(language)) {
          _fail(formsWhere, 'missing translation');
        }
        final forms = _object(map[language], formsWhere);
        _checkKeys(forms, _pluralForms, formsWhere);
        if (!forms.containsKey('other')) {
          _fail(formsWhere, 'a plural needs an "other" form');
        }
        formsByLanguage[language] = {
          for (final MapEntry(:key, :value) in forms.entries)
            key: _string(value, '$formsWhere.$key'),
        };
      }

      return _PluralText(count, formsByLanguage);
    }

    _checkKeys(map, productLanguages.toSet(), where);
    final byLanguage = <String, String>{};
    for (final language in productLanguages) {
      if (!map.containsKey(language)) {
        _fail('$where.$language', 'missing translation');
      }
      byLanguage[language] = _string(map[language], '$where.$language');
    }

    return _PlainText(byLanguage);
  }

  /// Parses a formula and checks it reads only names in [defined].
  Expression _formula(Object? json, String where, Set<String> defined) {
    final source = _string(json, where);
    final Expression formula;
    try {
      formula = Expression.parse(source);
    } on FormatException catch (error) {
      _fail(where, error.message);
    }
    final unknown = formula.variables.difference(defined);
    if (unknown.isNotEmpty) {
      _fail(
        where,
        'unknown variable(s) ${unknown.join(', ')}; '
        'a formula may read the inputs and the values defined before it',
      );
    }

    return formula;
  }

  void _define(Set<String> defined, String name, String where) {
    if (!_identifier.hasMatch(name) || _reservedNames.contains(name)) {
      _fail(where, '"$name" is not a valid name (letters, digits, _)');
    }
    if (!defined.add(name)) {
      _fail(where, '"$name" is already defined');
    }
  }

  Map<String, Object?> _object(Object? json, String where) {
    if (json is! Map<String, Object?>) {
      _fail(where, 'expected an object');
    }

    return json;
  }

  List<Object?> _list(Object? json, String where) {
    if (json is! List<Object?>) {
      _fail(where, 'expected a list');
    }

    return json;
  }

  String _string(Object? json, String where) {
    if (json is! String || json.isEmpty) {
      _fail(where, 'expected a non-empty string');
    }

    return json;
  }

  void _checkKeys(Map<String, Object?> map, Set<String> allowed, String where) {
    final unknown = map.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      _fail(
        where,
        'unknown key(s) ${unknown.join(', ')}; allowed: ${allowed.join(', ')}',
      );
    }
  }

  Never _fail(String where, String message) => throw FormatException(
    'Product "$id"${where.isEmpty ? '' : ', $where'}: $message',
  );
}
