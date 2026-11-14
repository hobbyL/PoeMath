import 'package:poemath/data/models/math_textbook_course.dart';

String mathTextbookAnswerLabel(MathTextbookAnswerKind kind) => switch (kind) {
  MathTextbookAnswerKind.number => '数值答案',
  MathTextbookAnswerKind.choice => '选择题',
  MathTextbookAnswerKind.comparison => '比较大小',
  MathTextbookAnswerKind.remainder => '商和余数',
  MathTextbookAnswerKind.expression => '算式或方程结果',
  MathTextbookAnswerKind.parent => '家长核对（作图、测量、开放题）',
};

String mathTextbookFormLabel(MathTextbookNumberForm form) => switch (form) {
  MathTextbookNumberForm.any => '等值即可',
  MathTextbookNumberForm.integer => '整数',
  MathTextbookNumberForm.decimal => '小数',
  MathTextbookNumberForm.fraction => '分数',
  MathTextbookNumberForm.simplestFraction => '最简分数',
  MathTextbookNumberForm.mixedNumber => '最简带分数',
  MathTextbookNumberForm.percentage => '百分数',
};

String mathTextbookPracticeLabel(MathTextbookPracticeKind kind) =>
    switch (kind) {
      MathTextbookPracticeKind.engine => '计算与数的关系',
      MathTextbookPracticeKind.unitConversion => '单位换算',
      MathTextbookPracticeKind.rectanglePerimeter => '长方形周长',
      MathTextbookPracticeKind.rectangleArea => '长方形面积',
      MathTextbookPracticeKind.triangleArea => '三角形面积',
      MathTextbookPracticeKind.trapezoidArea => '梯形面积',
      MathTextbookPracticeKind.circlePerimeter => '圆的周长',
      MathTextbookPracticeKind.circleArea => '圆的面积',
      MathTextbookPracticeKind.cuboidVolume => '长方体体积',
      MathTextbookPracticeKind.cubeVolume => '正方体体积',
      MathTextbookPracticeKind.cylinderVolume => '圆柱体体积',
      MathTextbookPracticeKind.dataTable => '统计表',
      MathTextbookPracticeKind.parentTask => '纸上实践，由家长核对',
    };

String mathTextbookResultLabel(MathTextbookResult result) => switch (result) {
  MathTextbookResult.correct => '自动核对通过',
  MathTextbookResult.incorrect => '需要再练',
  MathTextbookResult.pendingParent => '待家长核对',
  MathTextbookResult.parentCorrect => '家长核对通过',
  MathTextbookResult.parentAgain => '家长建议再练',
};
