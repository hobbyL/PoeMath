// test/math_engine/number_value_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/models/number_value.dart';

void main() {
  group('Fraction', () {
    test('基础创建', () {
      const f = Fraction(3, 4);
      expect(f.numerator, 3);
      expect(f.denominator, 4);
      expect(f.isInteger, isFalse);
    });

    test('整数分数', () {
      const f = Fraction(6, 3);
      expect(f.isInteger, isTrue);
      expect(f.asInteger, 2);
    });

    test('化简', () {
      const f = Fraction(6, 4);
      final s = f.simplified;
      expect(s.numerator, 3);
      expect(s.denominator, 2);
    });

    test('负数化简 - 负分母', () {
      const f = Fraction(3, -4);
      final s = f.simplified;
      expect(s.numerator, -3);
      expect(s.denominator, 4);
    });

    test('零分数', () {
      const f = Fraction(0, 5);
      final s = f.simplified;
      expect(s.numerator, 0);
      expect(s.denominator, 1);
    });

    test('加法', () {
      const a = Fraction(1, 4);
      const b = Fraction(1, 4);
      final result = a + b;
      expect(result, const Fraction(1, 2));
    });

    test('异分母加法', () {
      const a = Fraction(1, 3);
      const b = Fraction(1, 6);
      final result = a + b;
      expect(result, const Fraction(1, 2));
    });

    test('减法', () {
      const a = Fraction(3, 4);
      const b = Fraction(1, 4);
      final result = a - b;
      expect(result, const Fraction(1, 2));
    });

    test('乘法', () {
      const a = Fraction(2, 3);
      const b = Fraction(3, 4);
      final result = a * b;
      expect(result, const Fraction(1, 2));
    });

    test('除法', () {
      const a = Fraction(1, 2);
      const b = Fraction(3, 4);
      final result = a / b;
      expect(result, const Fraction(2, 3));
    });

    test('相等性', () {
      const a = Fraction(2, 4);
      const b = Fraction(1, 2);
      expect(a, equals(b));
    });

    test('比较运算符', () {
      const a = Fraction(3, 4);
      const b = Fraction(1, 2);
      expect(a > b, isTrue);
      expect(b < a, isTrue);
      expect(a >= a, isTrue);
      expect(b <= a, isTrue);
    });

    test('toString - 真分数', () {
      const f = Fraction(3, 4);
      expect(f.toString(), '3/4');
    });

    test('toString - 整数', () {
      const f = Fraction(6, 3);
      expect(f.toString(), '2');
    });

    test('toString - 带分数', () {
      const f = Fraction(5, 3);
      final s = f.simplified;
      expect(s.toString(), contains('/'));
    });

    test('toImproperString', () {
      const f = Fraction(5, 3);
      expect(f.toImproperString(), '5/3');
    });

    test('lcm 计算', () {
      expect(Fraction.lcm(4, 6), 12);
      expect(Fraction.lcm(3, 5), 15);
      expect(Fraction.lcm(7, 7), 7);
    });

    test('hashCode 一致性', () {
      const a = Fraction(2, 4);
      const b = Fraction(1, 2);
      expect(a.hashCode, b.hashCode);
    });

    test('asDouble', () {
      const f = Fraction(1, 4);
      expect(f.asDouble, 0.25);
    });
  });

  group('NumberValue', () {
    test('fromInt', () {
      final v = NumberValue.fromInt(42);
      expect(v.asInteger, 42);
      expect(v.isInteger, isTrue);
      expect(v.isNegative, isFalse);
    });

    test('fromInt 负数', () {
      final v = NumberValue.fromInt(-5);
      expect(v.isNegative, isTrue);
      expect(v.asInteger, -5);
    });

    test('fromDouble', () {
      final v = NumberValue.fromDouble(3.14);
      expect(v.asDouble, closeTo(3.14, 0.001));
      expect(v.isInteger, isFalse);
    });

    test('fromDouble 整数值', () {
      final v = NumberValue.fromDouble(5.0);
      expect(v.isInteger, isTrue);
      expect(v.asInteger, 5);
    });

    test('fromFraction', () {
      final v = NumberValue.fromFraction(3, 4);
      expect(v.asDouble, 0.75);
    });

    test('加法', () {
      final a = NumberValue.fromInt(3);
      final b = NumberValue.fromInt(5);
      final result = a + b;
      expect(result.asInteger, 8);
    });

    test('减法', () {
      final a = NumberValue.fromInt(10);
      final b = NumberValue.fromInt(3);
      final result = a - b;
      expect(result.asInteger, 7);
    });

    test('乘法', () {
      final a = NumberValue.fromInt(4);
      final b = NumberValue.fromInt(5);
      final result = a * b;
      expect(result.asInteger, 20);
    });

    test('除法', () {
      final a = NumberValue.fromInt(20);
      final b = NumberValue.fromInt(4);
      final result = a / b;
      expect(result.asInteger, 5);
    });

    test('分数运算', () {
      final a = NumberValue.fromFraction(1, 3);
      final b = NumberValue.fromFraction(1, 6);
      final result = a + b;
      expect(result.asFraction, const Fraction(1, 2));
    });

    test('比较运算符', () {
      final a = NumberValue.fromInt(5);
      final b = NumberValue.fromInt(3);
      expect(a > b, isTrue);
      expect(b < a, isTrue);
    });

    test('相等性', () {
      final a = NumberValue.fromInt(5);
      final b = NumberValue.fromInt(5);
      expect(a, equals(b));
    });

    test('toString - 整数', () {
      final v = NumberValue.fromInt(42);
      expect(v.toString(), '42');
    });

    test('toString - 小数', () {
      final v = NumberValue.fromDouble(3.14);
      expect(v.toString(), '3.14');
    });

    test('toFractionString', () {
      final v = NumberValue.fromFraction(3, 4);
      expect(v.toFractionString(), '3/4');
    });

    test('hashCode 一致性', () {
      final a = NumberValue.fromInt(5);
      final b = NumberValue.fromInt(5);
      expect(a.hashCode, b.hashCode);
    });
  });
}
