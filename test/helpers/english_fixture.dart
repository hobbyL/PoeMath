import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';

import 'textbook_fixture.dart';

Textbook englishBook({int pages = 12}) => textbookFixture(
  subject: TextbookSubject.english,
  title: '自有英语测试教材',
  pageCount: pages,
);
EnglishTarget englishWord({
  String id = 'word-1',
  String text = 'red kite',
  String meaning = '红风筝',
  bool approved = true,
  String origin = 'textbook',
}) {
  final target = EnglishTarget(
    id: id,
    kind: EnglishTargetKind.vocabulary,
    text: text,
    meaning: meaning,
    sources: const [EnglishSource(2, printedPage: '1')],
    spellingEnabled: true,
    origin: origin,
  );
  return approved ? target.approve(voiceKey: 'en-US|test') : target;
}

EnglishLesson englishLesson({
  String id = 'unit-1-p2',
  String unit = 'Unit 1 Garden',
  List<EnglishTarget>? targets,
}) => EnglishLesson(
  id: id,
  unitId: unit,
  title: 'Lesson 1',
  unitTitle: unit,
  startPage: 2,
  endPage: 3,
  prepared: true,
  targets:
      targets ??
      [
        englishWord(),
        englishWord(id: 'word-2', text: 'blue bird', meaning: '蓝鸟'),
        EnglishTarget(
          id: 'sentence-1',
          kind: EnglishTargetKind.sentence,
          text: 'I see a red kite.',
          sources: const [EnglishSource(3)],
        ).approve(),
        EnglishTarget(
          id: 'letter-1',
          kind: EnglishTargetKind.letter,
          text: 'B',
          sources: const [EnglishSource(3)],
        ).approve(),
        EnglishTarget(
          id: 'activity-1',
          kind: EnglishTargetKind.activity,
          text: 'Draw a bird.',
          sources: const [EnglishSource(3)],
        ).approve(),
      ],
);
EnglishCourse englishCourse({Textbook? book, List<EnglishLesson>? lessons}) {
  final b = book ?? englishBook();
  return EnglishCourse(
    bookId: b.pdfSha256,
    editionId: b.learningEditionId,
    pageCount: b.pageCount,
    fileSize: b.fileSize,
    lessons: lessons ?? [englishLesson()],
    coverage: {
      for (var p = 1; p <= b.pageCount; p++)
        p: p < 2
            ? '封面与导读'
            : p <= 3
            ? 'unit-1-p2'
            : '附录与词汇来源',
    },
  );
}
