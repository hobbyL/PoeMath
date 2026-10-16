import 'dart:convert';

import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';

/// 旧记录缺少快照时仍可按文本回练；过程错题须由调用端保留过程判分。
extension MathMistakeSnapshot on MathMistake {
  MathProblem? get originalProblem {
    if (problemJson == null) return null;
    try {
      return MathProblem.fromJson(
          jsonDecode(problemJson!) as Map<String, dynamic>,);
    } on Object {
      return null;
    }
  }

  VerticalAttempt? get originalAttempt {
    if (attemptJson == null) return null;
    try {
      return VerticalAttempt.fromJson(
          jsonDecode(attemptJson!) as Map<String, dynamic>,);
    } on Object {
      return null;
    }
  }
}
