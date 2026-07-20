import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/features/poem/poem_recite_page.dart';

void main() {
  test('ReciteLevel 与背诵掌握等级 1-4 一一对应', () {
    expect(ReciteLevel.easy.masteryLevel, 1);
    expect(ReciteLevel.medium.masteryLevel, 2);
    expect(ReciteLevel.hard.masteryLevel, 3);
    expect(ReciteLevel.dictation.masteryLevel, 4);
  });
}
