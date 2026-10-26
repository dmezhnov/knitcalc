/// The small formula language product definitions are written in.
///
/// A product's JSON file describes its calculations as strings such as
/// `round(stitchesPerCm * shoulderWidthCm)`; [Expression.parse] turns one into
/// a tree once, at load time, and [Expression.evaluate] runs it against the
/// entered values on every rebuild.
///
/// The language is deliberately tiny:
///   * numbers (`2`, `0.005`), `null`, `true` and `false`;
///   * variables — a product's inputs and its earlier named values;
///   * `+ - * / %`, unary `-` and `!`, comparisons `< <= > >= == !=`,
///     `&&`, `||` and the conditional `cond ? a : b`;
///   * the functions in [_functions] (`round`, `floor`, `ceil`, `abs`, `min`,
///     `max`).
///
/// Every value is a `double?`. Booleans are `1` and `0`, and a condition is
/// true when it is neither `null` nor `0`. `null` means "cannot be computed"
/// (the UI shows a dash): arithmetic on it stays `null` and ordering
/// comparisons with it are false. Division and remainder by zero give `0`,
/// the calculator's convention for a half-filled form.
library;

/// A parsed formula.
sealed class Expression {
  const Expression();

  /// Parses [source], throwing a [FormatException] that points at the
  /// offending character when it is not a valid formula.
  factory Expression.parse(String source) => _Parser(source).parse();

  /// Computes the value with the variables taken from [scope]. Every name in
  /// [variables] must be present in it.
  double? evaluate(Map<String, double?> scope);

  /// Every variable name the formula reads, so a product can be checked for
  /// misspelt names when it is loaded rather than when a user opens it.
  Set<String> get variables;
}

/// Whether [value] counts as true in a condition.
bool isTruthy(double? value) => value != null && value != 0;

double _fromBool(bool value) => value ? 1 : 0;

class _Number extends Expression {
  const _Number(this.value);

  final double? value;

  @override
  double? evaluate(Map<String, double?> scope) => value;

  @override
  Set<String> get variables => const {};
}

class _Variable extends Expression {
  const _Variable(this.name);

  final String name;

  @override
  double? evaluate(Map<String, double?> scope) {
    if (!scope.containsKey(name)) {
      throw StateError('Unknown variable "$name"');
    }

    return scope[name];
  }

  @override
  Set<String> get variables => {name};
}

class _Unary extends Expression {
  const _Unary(this.operator, this.operand);

  final String operator;
  final Expression operand;

  @override
  double? evaluate(Map<String, double?> scope) {
    final value = operand.evaluate(scope);

    return switch (operator) {
      '!' => _fromBool(!isTruthy(value)),
      '-' => value == null ? null : -value,
      _ => throw StateError('Unknown unary operator "$operator"'),
    };
  }

  @override
  Set<String> get variables => operand.variables;
}

class _Binary extends Expression {
  const _Binary(this.operator, this.left, this.right);

  final String operator;
  final Expression left;
  final Expression right;

  @override
  double? evaluate(Map<String, double?> scope) {
    // The logical operators short-circuit, so a guard such as
    // `rows > 0 && stitches / rows > 1` never evaluates its right side when
    // the left one already decides the result.
    if (operator == '&&') {
      return _fromBool(
        isTruthy(left.evaluate(scope)) && isTruthy(right.evaluate(scope)),
      );
    }
    if (operator == '||') {
      return _fromBool(
        isTruthy(left.evaluate(scope)) || isTruthy(right.evaluate(scope)),
      );
    }

    final a = left.evaluate(scope);
    final b = right.evaluate(scope);

    if (operator == '==') {
      return _fromBool(a == b);
    }
    if (operator == '!=') {
      return _fromBool(a != b);
    }
    if (a == null || b == null) {
      // Arithmetic on an unknown value stays unknown; an ordering against it
      // is simply not satisfied.
      return const {'<', '<=', '>', '>='}.contains(operator) ? 0 : null;
    }

    return switch (operator) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      '/' => b == 0 ? 0 : a / b,
      '%' => b == 0 ? 0 : a % b,
      '<' => _fromBool(a < b),
      '<=' => _fromBool(a <= b),
      '>' => _fromBool(a > b),
      '>=' => _fromBool(a >= b),
      _ => throw StateError('Unknown binary operator "$operator"'),
    };
  }

  @override
  Set<String> get variables => {...left.variables, ...right.variables};
}

class _Conditional extends Expression {
  const _Conditional(this.condition, this.then, this.otherwise);

  final Expression condition;
  final Expression then;
  final Expression otherwise;

  @override
  double? evaluate(Map<String, double?> scope) =>
      isTruthy(condition.evaluate(scope))
      ? then.evaluate(scope)
      : otherwise.evaluate(scope);

  @override
  Set<String> get variables => {
    ...condition.variables,
    ...then.variables,
    ...otherwise.variables,
  };
}

/// A built-in function: how many arguments it takes and what it computes from
/// them once none of them is `null`.
class _Function {
  const _Function(this.arity, this.compute);

  final int arity;
  final double Function(List<double> arguments) compute;
}

/// The functions a formula may call. `round` rounds half away from zero, the
/// way [double.roundToDouble] does.
final Map<String, _Function> _functions = {
  'round': _Function(1, (a) => a[0].roundToDouble()),
  'floor': _Function(1, (a) => a[0].floorToDouble()),
  'ceil': _Function(1, (a) => a[0].ceilToDouble()),
  'abs': _Function(1, (a) => a[0].abs()),
  'min': _Function(2, (a) => a[0] < a[1] ? a[0] : a[1]),
  'max': _Function(2, (a) => a[0] > a[1] ? a[0] : a[1]),
};

class _Call extends Expression {
  const _Call(this.function, this.arguments);

  final _Function function;
  final List<Expression> arguments;

  @override
  double? evaluate(Map<String, double?> scope) {
    final values = [for (final argument in arguments) argument.evaluate(scope)];
    if (values.contains(null)) {
      return null;
    }

    return function.compute(values.cast<double>());
  }

  @override
  Set<String> get variables => {
    for (final argument in arguments) ...argument.variables,
  };
}

/// Recursive-descent parser; each method handles one precedence level, from
/// the loosest (the conditional) to the tightest (a single operand).
class _Parser {
  _Parser(this.source);

  final String source;
  int _position = 0;

  Expression parse() {
    final expression = _conditional();
    _skipSpaces();
    if (_position < source.length) {
      _fail('Unexpected "${source[_position]}"');
    }

    return expression;
  }

  Expression _conditional() {
    final condition = _binary(0);
    if (!_accept('?')) {
      return condition;
    }
    final then = _conditional();
    _expect(':');
    final otherwise = _conditional();

    return _Conditional(condition, then, otherwise);
  }

  /// Binary operators grouped by precedence, loosest first. Longer operators
  /// come before their prefixes (`<=` before `<`) so they match first.
  static const List<List<String>> _levels = [
    ['||'],
    ['&&'],
    ['==', '!='],
    ['<=', '>=', '<', '>'],
    ['+', '-'],
    ['*', '/', '%'],
  ];

  Expression _binary(int level) {
    if (level == _levels.length) {
      return _unary();
    }

    var left = _binary(level + 1);
    while (true) {
      final operator = _acceptAny(_levels[level]);
      if (operator == null) {
        return left;
      }
      left = _Binary(operator, left, _binary(level + 1));
    }
  }

  Expression _unary() {
    final operator = _acceptAny(const ['-', '!']);
    if (operator != null) {
      return _Unary(operator, _unary());
    }

    return _operand();
  }

  Expression _operand() {
    _skipSpaces();
    if (_accept('(')) {
      final inner = _conditional();
      _expect(')');

      return inner;
    }

    final number = _match(RegExp(r'\d+(\.\d+)?'));
    if (number != null) {
      return _Number(double.parse(number));
    }

    final name = _match(RegExp(r'[A-Za-z_]\w*'));
    if (name == null) {
      _fail(
        _position < source.length
            ? 'Unexpected "${source[_position]}"'
            : 'Unexpected end of formula',
      );
    }

    return switch (name) {
      'null' => const _Number(null),
      'true' => const _Number(1),
      'false' => const _Number(0),
      _ => _accept('(') ? _call(name) : _Variable(name),
    };
  }

  Expression _call(String name) {
    final function = _functions[name];
    if (function == null) {
      _fail('Unknown function "$name"');
    }

    final arguments = <Expression>[];
    if (!_accept(')')) {
      do {
        arguments.add(_conditional());
      } while (_accept(','));
      _expect(')');
    }
    if (arguments.length != function.arity) {
      _fail(
        '"$name" takes ${function.arity} argument(s), '
        'got ${arguments.length}',
      );
    }

    return _Call(function, arguments);
  }

  void _skipSpaces() {
    while (_position < source.length && source[_position].trim().isEmpty) {
      _position++;
    }
  }

  /// Consumes [token] when it comes next.
  bool _accept(String token) {
    _skipSpaces();
    if (!source.startsWith(token, _position)) {
      return false;
    }
    _position += token.length;

    return true;
  }

  /// Consumes the first of [tokens] that comes next and returns it.
  String? _acceptAny(List<String> tokens) {
    for (final token in tokens) {
      if (_accept(token)) {
        return token;
      }
    }

    return null;
  }

  void _expect(String token) {
    if (!_accept(token)) {
      _fail('Expected "$token"');
    }
  }

  String? _match(RegExp pattern) {
    final match = pattern.matchAsPrefix(source, _position);
    if (match == null) {
      return null;
    }
    _position = match.end;

    return match[0];
  }

  Never _fail(String message) =>
      throw FormatException('$message in formula "$source"', source, _position);
}
