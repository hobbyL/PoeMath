// lib/math_engine/models/number_value.dart
//
// 统一数值类型：支持整数、小数、分数三种表示。
// 所有口算引擎内部运算均基于此类型。

/// 分数表示（a/b 形式）。
class Fraction {
  final int numerator;
  final int denominator;

  const Fraction(this.numerator, [this.denominator = 1])
      : assert(denominator != 0, '分母不能为零');

  /// 化简到最简分数。
  Fraction get simplified {
    if (numerator == 0) return const Fraction(0, 1);
    final g = _gcd(numerator.abs(), denominator.abs());
    final sign = denominator < 0 ? -1 : 1;
    return Fraction(sign * numerator ~/ g, sign * denominator ~/ g);
  }

  /// 是否为整数（分母为 1 或能整除）。
  bool get isInteger => numerator % denominator == 0;

  int get asInteger => numerator ~/ denominator;

  double get asDouble => numerator / denominator;

  Fraction operator +(Fraction other) {
    return Fraction(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator,
    ).simplified;
  }

  Fraction operator -(Fraction other) {
    return Fraction(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator,
    ).simplified;
  }

  Fraction operator *(Fraction other) {
    return Fraction(
      numerator * other.numerator,
      denominator * other.denominator,
    ).simplified;
  }

  Fraction operator /(Fraction other) {
    assert(other.numerator != 0, '除数不能为零');
    return Fraction(
      numerator * other.denominator,
      denominator * other.numerator,
    ).simplified;
  }

  bool operator >(Fraction other) => asDouble > other.asDouble;
  bool operator <(Fraction other) => asDouble < other.asDouble;
  bool operator >=(Fraction other) => asDouble >= other.asDouble;
  bool operator <=(Fraction other) => asDouble <= other.asDouble;

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      simplified.numerator == other.simplified.numerator &&
      simplified.denominator == other.simplified.denominator;

  @override
  int get hashCode {
    final s = simplified;
    return Object.hash(s.numerator, s.denominator);
  }

  @override
  String toString() {
    if (isInteger) return asInteger.toString();
    final s = simplified;
    if (s.numerator.abs() > s.denominator) {
      // 带分数形式
      final whole = s.numerator ~/ s.denominator;
      final remainder = (s.numerator % s.denominator).abs();
      return '$whole $remainder/${s.denominator}';
    }
    return '${s.numerator}/${s.denominator}';
  }

  /// 输出为纯分数字符串（不转带分数）。
  String toImproperString() {
    if (isInteger) return asInteger.toString();
    final s = simplified;
    return '${s.numerator}/${s.denominator}';
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }

  /// 求两个整数的最小公倍数。
  static int lcm(int a, int b) => (a * b).abs() ~/ _gcd(a.abs(), b.abs());
}

/// 统一数值：可以是整数、小数或分数。
class NumberValue {
  final Fraction _value;

  /// 从整数创建。
  NumberValue.fromInt(int value) : _value = Fraction(value);

  /// 从小数创建（精度 4 位）。
  NumberValue.fromDouble(double value)
      : _value = _doubleToFraction(value).simplified;

  /// 从分数创建。
  NumberValue.fromFraction(int numerator, int denominator)
      : _value = Fraction(numerator, denominator).simplified;

  /// 直接包装 Fraction。
  NumberValue.fromFractionObj(this._value);

  Fraction get asFraction => _value.simplified;
  int get asInteger => _value.asInteger;
  double get asDouble => _value.asDouble;
  bool get isInteger => _value.isInteger;
  bool get isNegative => _value.numerator < 0;

  NumberValue operator +(NumberValue other) =>
      NumberValue.fromFractionObj(_value + other._value);

  NumberValue operator -(NumberValue other) =>
      NumberValue.fromFractionObj(_value - other._value);

  NumberValue operator *(NumberValue other) =>
      NumberValue.fromFractionObj(_value * other._value);

  NumberValue operator /(NumberValue other) =>
      NumberValue.fromFractionObj(_value / other._value);

  bool operator >(NumberValue other) => _value > other._value;
  bool operator <(NumberValue other) => _value < other._value;
  bool operator >=(NumberValue other) => _value >= other._value;
  bool operator <=(NumberValue other) => _value <= other._value;

  @override
  bool operator ==(Object other) =>
      other is NumberValue && _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() {
    if (_value.isInteger) return _value.asInteger.toString();
    // 尝试精确小数表示
    final d = _value.asDouble;
    final s = d.toString();
    // 如果小数位数 ≤ 4，使用小数表示
    final dotIndex = s.indexOf('.');
    if (dotIndex >= 0 && s.length - dotIndex - 1 <= 4) {
      // 去除末尾多余的零
      return _trimTrailingZeros(s);
    }
    return _value.toString();
  }

  /// 以分数形式输出。
  String toFractionString() => _value.toImproperString();

  static String _trimTrailingZeros(String s) {
    if (!s.contains('.')) return s;
    var result = s;
    while (result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static Fraction _doubleToFraction(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e9) {
      return Fraction(value.round());
    }
    // 用有限精度转换
    const precision = 10000;
    final numerator = (value * precision).round();
    return Fraction(numerator, precision);
  }
}
