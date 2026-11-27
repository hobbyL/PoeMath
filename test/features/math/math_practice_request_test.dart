import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

void main() {
  const legacy = MathPracticeRequest(
    grade: 3,
    semester: '下',
    count: 10,
    difficulty: DifficultyLevel.medium,
  );
  test('旧请求保持自动，新次数往返且冻结调用方集合', () {
    expect(
      MathPracticeRequest.fromJson(legacy.toJson()).operationCounts,
      isNull,
    );
    final values = [3, 2];
    final request = MathPracticeRequest(
      grade: 3,
      semester: '下',
      count: 10,
      difficulty: DifficultyLevel.medium,
      operationCounts: OperationCounts(values),
    );
    values.clear();
    expect(request.toJson()['operationCounts'], [2, 3]);
    expect(
      MathPracticeRequest.fromJson(request.toJson()).toJson(),
      request.toJson(),
    );
  });

  test('坏次数和专项冲突的请求不能恢复', () {
    for (final counts in <Object>[
      [],
      [1, 1],
      [4],
      ['2'],
      [2.0],
    ]) {
      expect(
        () => MathPracticeRequest.fromJson({
          ...legacy.toJson(),
          'operationCounts': counts,
        }),
        throwsFormatException,
      );
    }
    for (final extra in <Map<String, dynamic>>[
      {'skillId': 'operation_order'},
      {'mode': 'vertical'},
      {'verticalProcessOnly': true},
      {'mode': 'withBrackets'},
      {'mode': 'chain'},
    ]) {
      expect(
        () => MathPracticeRequest.fromJson({
          ...legacy.toJson(),
          'operationCounts': [1],
          ...extra,
        }),
        throwsFormatException,
      );
    }
  });
}
