import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/math/widgets/vertical_calc_widget.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

void main() {
  testWidgets('小数加减补齐小数位，整数的个位不会对到小数位', (tester) async {
    final problem = MathProblem(
      operands: [NumberValue.fromDouble(352.5), NumberValue.fromInt(202)],
      operators: const [Operator.subtract],
      result: NumberValue.fromDouble(150.5),
      mode: ProblemMode.vertical,
      grade: 4,
      resultForm: ResultForm.decimal,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
              child: VerticalCalcWidget(problem: problem, showAnswer: true),),
        ),
      ),
    );
    expect(find.text('352.5'), findsOneWidget);
    expect(find.text('202.0'), findsOneWidget);
    expect(find.text('150.5'), findsOneWidget);
    final a = tester.getRect(find.text('352.5'));
    final b = tester.getRect(find.text('202.0'));
    expect(a.right, b.right);
    expect(a.width, b.width);
  });
}
