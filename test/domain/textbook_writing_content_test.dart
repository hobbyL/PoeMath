import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/domain/textbook_course_mutations.dart';
import 'package:poemath/domain/textbook_writing_content.dart';
import 'package:poemath/domain/writing_stroke_data.dart';

import '../helpers/textbook_course_fixture.dart';
import '../helpers/writing_fixture.dart';

/// 真实资产中缺数据的补充平面字符（Make Me a Hanzi 未收录）。
const _missingCharacter = '𠀀';

bool _hasStrokeData(String character) => character != _missingCharacter;

/// 在 fixture 末尾追加一个"无笔顺数据"的会写字，用于覆盖 AC6 降级链路。
TextbookCoursePack _withRareTarget(TextbookCoursePack pack) {
  final raw = pack.toJson();
  final lesson = (raw['lessons'] as List).single as Map<String, dynamic>;
  final characters = lesson['writingCharacters'] as List;
  if (characters.cast<Map<String, dynamic>>().any(
        (node) => node['text'] == _missingCharacter,
      )) {
    return pack;
  }
  characters.add({
    ...courseFixtureText('write-rare', _missingCharacter, ['hē']),
    'requirement': 'writing',
  });
  return TextbookCoursePack.fromJson(raw);
}

List<WritingTarget> _targets(TextbookCoursePack pack) => writingTargets(
      pack,
      pack.lessons.single,
      hasStrokeData: _hasStrokeData,
    );

void main() {
  test('从教材会写字构建写字目标，保留顺序、注音与笔顺数据可用性', () {
    final pack = _withRareTarget(writingFixture());
    final lesson = pack.lessons.single;
    final targets = _targets(pack);

    expect(
      targets.map((t) => t.id).toList(),
      lesson.writingCharacters.map((n) => n.id).toList(),
    );
    expect(
      targets.map((t) => t.text).toList(),
      lesson.writingCharacters.map((n) => n.text).toList(),
    );
    expect(
      targets.map((t) => t.pinyin).toList(),
      lesson.writingCharacters.map((n) => n.pinyin!.first).toList(),
    );
    expect(targets.first.hasStrokeData, isTrue);
    expect(targets.last.hasStrokeData, isFalse);
    expect(targets.last.text, _missingCharacter);
    expect(targets.every((t) => t.node.requirement == 'writing'), isTrue);
  });

  test('科目无会写字时返回空列表，课级指纹稳定', () {
    final raw = writingFixture().toJson();
    final lessonRaw = (raw['lessons'] as List).single as Map<String, dynamic>;
    lessonRaw['writingCharacters'] = <Object?>[];
    lessonRaw['coverage'] = {
      ...(lessonRaw['coverage'] as Map<String, dynamic>),
      'writingCharacters': 'notApplicable',
    };
    final pack = TextbookCoursePack.fromJson(raw);
    expect(_targets(pack), isEmpty);
    expect(
      writingLessonFingerprint(const []),
      writingLessonFingerprint(_targets(pack)),
    );
  });

  test('字级指纹同内容可复现，换字即变化', () {
    final pack = writingFixture();
    final lesson = pack.lessons.single;
    final target = lesson.writingCharacters.first;
    final fingerprint = writingTargetFingerprint(
      pack: pack,
      lesson: lesson,
      target: target,
      hasStrokeData: true,
    );
    expect(
      writingTargetFingerprint(
        pack: pack,
        lesson: lesson,
        target: target,
        hasStrokeData: true,
      ),
      fingerprint,
    );

    final changed = addTextbookCourseTarget(
      pack,
      lesson.id,
      'writingCharacters',
      id: 'write-new',
      text: '水',
    );
    final newLesson = changed.lessons.single;
    final newTarget =
        newLesson.writingCharacters.firstWhere((n) => n.id == 'write-new');
    expect(
      writingTargetFingerprint(
        pack: changed,
        lesson: newLesson,
        target: newTarget,
        hasStrokeData: true,
      ),
      isNot(fingerprint),
    );
  });

  test('笔顺数据可用性变化即令指纹失效（资产覆盖变化 → 旧进度作废）', () {
    final pack = writingFixture();
    final lesson = pack.lessons.single;
    final target = lesson.writingCharacters.first;
    expect(
      writingTargetFingerprint(
        pack: pack,
        lesson: lesson,
        target: target,
        hasStrokeData: true,
      ),
      isNot(
        writingTargetFingerprint(
          pack: pack,
          lesson: lesson,
          target: target,
          hasStrokeData: false,
        ),
      ),
    );
  });

  test('课级指纹随目标顺序变化（顺序即书写事实的一部分）', () {
    final targets = _targets(writingFixture());
    final fingerprint = writingLessonFingerprint(targets);
    expect(
      writingLessonFingerprint(targets.reversed.toList()),
      isNot(fingerprint),
    );
  });

  test('同课只改一字内容也会令课级指纹失效', () {
    final pack = writingFixture();
    final lesson = pack.lessons.single;
    final before = writingLessonFingerprint(_targets(pack));

    final edited = editTextbookCourseNode(
      pack,
      lesson.writingCharacters.first.id,
      {'text': '日', 'pinyin': ['rì']},
    );
    expect(edited.lessons.single.writingCharacters.first.text, '日');
    expect(
      writingLessonFingerprint(_targets(edited)),
      isNot(before),
    );
  });

  test('真实笔顺资产覆盖 fixture 中的字，缺字返回 null 不抛错', () async {
    resetWritingStrokeDataForTest();
    addTearDown(resetWritingStrokeDataForTest);
    expect(hasStrokeDataSync('星'), isFalse, reason: '未加载时应为 false');

    final star = await strokeDataFor('星');
    expect(star, isNotNull);
    expect(star!.character, '星');
    expect(star.strokeCount, greaterThan(0));
    expect(star.strokes.length, star.medians.length);
    expect(star.medians.every((stroke) => stroke.isNotEmpty), isTrue);
    expect(hasStrokeDataSync('星'), isTrue);
    expect(hasStrokeDataSync(_missingCharacter), isFalse);
    expect(await strokeDataFor(_missingCharacter), isNull);
  });

  test('资产加载失败抛出可捕获异常，且失败不污染缓存可重试', () async {
    resetWritingStrokeDataForTest();
    addTearDown(resetWritingStrokeDataForTest);

    await expectLater(
      loadWritingStrokeData(
        loader: (_) async => throw StateError('模拟资产缺失'),
      ),
      throwsA(isA<WritingStrokeDataException>()),
    );
    expect(hasStrokeDataSync('星'), isFalse);

    final recovered = await loadWritingStrokeData();
    expect(recovered.containsKey('星'), isTrue);
  });

  test('坏资产（非 gzip）抛可捕获异常', () async {
    resetWritingStrokeDataForTest();
    addTearDown(resetWritingStrokeDataForTest);
    await expectLater(
      loadWritingStrokeData(loader: (_) async => Uint8List.fromList([1, 2, 3])),
      throwsA(isA<WritingStrokeDataException>()),
    );
  });
}