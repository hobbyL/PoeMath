import 'dart:math' as math;

import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/domain/textbook_pinyin_font.dart';
import 'package:poemath/domain/textbook_text_display.dart';
import 'package:poemath/domain/textbook_reading_pipeline.dart';

class TextbookParsedLesson {
  const TextbookParsedLesson(
    this.lesson,
    this.candidates, {
    required this.sourceAnchored,
  });
  final Map<String, dynamic> lesson;
  final List<TextbookDraftCandidate> candidates;
  final bool sourceAnchored;
}

/// 可独立测试的确定性规则。原书证据不足时保留候选，不猜读音或答案。
class TextbookCourseDraftParser {
  static const version = 9;
  final _reading = TextbookReadingPipeline();

  TextbookReadingLayout readingLayout(
    TextbookCourseParagraph paragraph,
    List<TextbookPageText> pages, {
    bool preserveLines = false,
    List<TextbookCourseParagraph> paragraphs = const [],
  }) =>
      _reading.readingLayout(
        paragraph,
        pages,
        preserveLines: preserveLines,
        paragraphs: paragraphs,
      );

  TextbookCourseDocument seed(
    TextbookCatalogEntry entry,
    TextbookTocResult toc, {
    TextbookCoursePack? existing,
    List<TextbookDraftPlan> previousPlans = const [],
  }) {
    if (toc.entries.where((e) => !e.isGroup && e.page != null).isEmpty) {
      throw const FormatException('未找到可定位的课目；请先打开原书确认目录和文字层');
    }
    final book = entry.book;
    final units = <Map<String, dynamic>>[];
    final lessons = <Map<String, dynamic>>[];
    final plans = <TextbookDraftPlan>[];
    Map<String, dynamic>? unit;
    final used = <String>{};
    final reservedLessons = {...?existing?.lessons.map((l) => l.id)};
    final reservedUnits = {...?existing?.units.map((u) => u.id)};
    final tocTitles = toc.entries
        .where((e) => !e.isGroup)
        .map((e) => _reading.titleKey(e.title))
        .toSet();
    String fresh(String prefix, Set<String> reserved) {
      var number = 1;
      while (reserved.contains('$prefix-$number')) {
        number++;
      }
      final id = '$prefix-$number';
      reserved.add(id);
      return id;
    }

    for (final item in toc.entries) {
      if (item.isGroup) {
        final old =
            existing?.units.where((u) => u.title == item.title).firstOrNull;
        unit = {
          'id': old?.id ?? fresh('auto-u', reservedUnits),
          'title': item.title,
          'sources': [for (final p in toc.directoryPages) _source(p)],
          'review': newTextbookReview(),
          'lessonIds': <String>[],
        };
        if (!units.any((u) => u['id'] == unit!['id'])) units.add(unit);
        continue;
      }
      if (item.page == null || item.page! < 1 || item.page! > book.pageCount) {
        continue;
      }
      if (unit == null) {
        unit = {
          'id': fresh('auto-u', reservedUnits),
          'title': '原书课目',
          'sources': [for (final p in toc.directoryPages) _source(p)],
          'review': newTextbookReview(),
          'lessonIds': <String>[],
        };
        units.add(unit);
      }
      final available = previousPlans.where((p) => !used.contains(p.id));
      final atPage = available
          .where(
            (p) =>
                p.startPage == item.page &&
                !tocTitles.contains(_reading.titleKey(p.title)),
          )
          .toList();
      final mapped = available
              .where(
                (p) =>
                    _reading.titleKey(p.title) == _reading.titleKey(item.title),
              )
              .firstOrNull ??
          (atPage.length == 1 ? atPage.single : null);
      final old = existing?.lessons
          .where(
            (l) =>
                !used.contains(l.id) &&
                (l.id == mapped?.id ||
                    _reading.titleKey(l.title) ==
                        _reading.titleKey(item.title)),
          )
          .firstOrNull;
      final id = old?.id ?? fresh('auto-l', reservedLessons);
      if (!used.add(id)) continue;
      if (old != null && old.unitId != unit['id']) {
        final oldUnit = existing!.units.firstWhere((u) => u.id == old.unitId);
        unit = units.where((u) => u['id'] == oldUnit.id).firstOrNull ??
            {
              'id': oldUnit.id,
              'title': oldUnit.title,
              'sources': oldUnit.toJson()['sources'],
              'review': newTextbookReview(),
              'lessonIds': <String>[],
            };
        if (!units.contains(unit)) units.add(unit);
      }
      (unit['lessonIds'] as List).add(id);
      lessons.add({
        'id': id,
        'unitId': unit['id'],
        'title': item.title,
        'kind': _kind(item.title, unit['title'] as String),
        'lessonNumber': item.lessonNumber,
        'sources': [_source(item.page!, printed: item.printedPage)],
        'review': newTextbookReview(),
        'coverage': {
          for (final c in TextbookCoursePack.categories) c: 'pending',
        },
        for (final c in TextbookCoursePack.categories) c: <dynamic>[],
      });
      plans.add(
        TextbookDraftPlan(
          id: id,
          startPage: item.page!,
          endPage: book.pageCount,
          title: item.title,
          printedPage: item.printedPage,
        ),
      );
    }
    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      final next = i + 1 < plans.length ? plans[i + 1] : null;
      // 包含下一课的首页，用标题锚点切同页内容；不以“下一页-1”代替正文边界。
      plans[i] = TextbookDraftPlan(
        id: plan.id,
        startPage: plan.startPage,
        endPage: math.max(plan.startPage, next?.startPage ?? book.pageCount),
        title: plan.title,
        nextTitle: next?.title,
        printedPage: plan.printedPage,
      );
    }
    final pack = TextbookCoursePack.fromJson({
      'schemaVersion': 1,
      'kind': 'textbookCourse',
      'status': 'draft',
      'contentRevision': 1,
      'coverage': 'partial',
      'expectedLessonCount': null,
      'edition': {
        'id':
            'yuwen-g${book.grade}-${book.semester == '上' ? 'first' : 'second'}-${book.pdfSha256.substring(0, 12)}',
        'pdfSha256': book.pdfSha256,
        'pageCount': book.pageCount,
        'fileSize': book.fileSize,
        'title': book.title,
        'grade': book.grade,
        'semester': book.semester,
        'publisher': book.publisher,
        'editionLabel': entry.editionLabel,
        'editionNotes': book.editionNote,
        'publicationDate': entry.publicationDate,
        'editionNumber': entry.editionNumber,
        'printingDate': entry.printingDate,
        'printingNumber': entry.printingNumber,
        'sourceUrl': entry.downloadUrl.toString(),
        'sources': [for (final p in entry.evidencePdfPages) _source(p)],
        'review': newTextbookReview(),
      },
      'permissions': {
        'content': {'status': 'unknown', 'evidence': ''},
        'applicationUse': {'status': 'unknown', 'evidence': ''},
      },
      'review': newTextbookReview(),
      'units': units.where((u) => (u['lessonIds'] as List).isNotEmpty).toList(),
      'lessons': lessons,
    });
    return TextbookCourseDocument(
      pack,
      TextbookDraftManifest(
        runId: DateTime.now().microsecondsSinceEpoch.toString(),
        parserVersion: version,
        phase: 'running',
        plans: plans,
        baselines: {
          for (final l in lessons) l['id'] as String: textbookDraftBaseline(l),
        },
      ),
    );
  }

  String _kind(String title, String unit) => !_reading.hasHan(title)
      ? 'other'
      : title.contains('园地')
          ? 'garden'
          : title.contains('口语交际')
              ? 'oral'
              : title.contains('习作')
                  ? 'writing'
                  : title.contains('识字表') ||
                          title.contains('写字表') ||
                          title.contains('词语表')
                      ? 'appendix'
                      : title.contains('古诗')
                          ? 'poetry'
                          : unit.contains('识字')
                              ? 'literacy'
                              : 'text';

  Map<String, dynamic> _source(
    int page, {
    int? printed,
    String status = 'text_extracted',
  }) =>
      {
        'pdfPage': page,
        'printedPage': printed?.toString(),
        'extractionStatus': status,
      };
  TextbookParsedLesson parse(
    TextbookCourseLesson skeleton,
    TextbookDraftPlan plan,
    List<TextbookPageText> pages, {
    List<TextbookDraftCandidate> vocabulary = const [],
  }) {
    final raw = skeleton.toJson();
    if (!_reading.hasHan(skeleton.title)) raw['kind'] = 'other';
    raw['review'] = newTextbookReview();
    raw['coverage'] = {
      for (final c in TextbookCoursePack.categories) c: 'pending',
    };
    for (final c in TextbookCoursePack.categories) {
      raw[c] = <dynamic>[];
    }
    final analysis =
        _reading.analyze(skeleton, plan, pages, vocabulary: vocabulary);
    final candidates = analysis.candidates.toList();
    final instructions = analysis.instructions;
    final paragraphs = raw['paragraphs'] as List;
    for (final paragraph in analysis.paragraphs) {
      final group = paragraph.lines;
      final first = group.first;
      final firstIndent = paragraph.leadingIndent;
      final text = [
        firstIndent ? '　　${first.text.trim()}' : first.text.trim(),
        for (final row in group.skip(1)) row.text.trim(),
      ].join('\n');
      final id =
          '${plan.id}-p-${group.first.page}-${group.first.glyphs.first.index}';
      final tokens = <String>[];
      var complete = true;
      final hints = <String>[];
      for (final row in group) {
        for (final glyph in row.glyphs) {
          if (glyph.text.trim().isEmpty) continue;
          if (!_reading.hasHan(glyph.text)) {
            tokens.add(glyph.text);
            continue;
          }
          final rawHint = _reading.pinyinFor(glyph, row, pages);
          final hint =
              rawHint == null ? null : decodeTextbookPinyinFont(rawHint);
          final valid = hint != null && isTextbookPinyin(hint);
          if (!valid) complete = false;
          tokens.add(valid ? hint : '');
          if (!valid) {
            // 只把真正待补齐的字放进候选；有效注音不再重复铺满卡片。
            hints.add(
              '${glyph.text}: ${rawHint == null ? '未找到注音' : hint ?? '字体编码待核对'}',
            );
          }
        }
      }
      final node = {
        'id': id,
        'text': text,
        'pinyin': complete ? tokens : null,
        'sources': [
          for (final p in group.map((r) => r.page).toSet())
            _source(
              p,
              printed: plan.printedPage == null
                  ? null
                  : plan.printedPage! + p - plan.startPage,
            ),
        ],
        'review': newTextbookReview(),
      };
      paragraphs.add(node);
      if (!complete && hints.isNotEmpty) {
        candidates.add(
          TextbookDraftCandidate(
            id: '$id-pinyin',
            text: text,
            reason: '局部注音或字体编码待补齐；正文注音暂为空',
            pages: group.map((r) => r.page).toSet().toList(),
            pinyin: hints,
          ),
        );
      }
    }
    for (final candidate in vocabulary) {
      if (candidate.category == 'recognitionCharacters' ||
          candidate.category == 'writingCharacters' ||
          candidate.category == 'words') {
        final targets = raw[candidate.category] as List;
        for (final text in candidate.category == 'words'
            ? candidate.text.split(RegExp(r'\s+'))
            : candidate.text.runes
                .map(String.fromCharCode)
                .where(_reading.hasHan)) {
          if (text.isEmpty) continue;
          final prior = targets
              .cast<Map<String, dynamic>>()
              .where((n) => n['text'] == text)
              .firstOrNull;
          if (prior != null) {
            final sources = prior['sources'] as List;
            for (final page in candidate.pages) {
              if (!sources.any((s) => (s as Map)['pdfPage'] == page)) {
                sources.add(_source(page));
              }
            }
            continue;
          }
          targets.add({
            'id':
                '${plan.id}-${candidate.category == 'words' ? 'word' : candidate.category == 'writingCharacters' ? 'w' : 'r'}-${textbookTextDigest(text).substring(0, 16)}',
            'text': text,
            'pinyin': null,
            'requirement': candidate.category == 'words'
                ? 'reading'
                : candidate.category == 'writingCharacters'
                    ? 'writing'
                    : 'recognition',
            'sources': [for (final p in candidate.pages) _source(p)],
            'review': newTextbookReview(),
          });
        }
      } else {
        candidates.add(candidate);
      }
    }
    // 指令按视觉行组合，保留续行与图示依赖；没有原书答案则不生成答案。
    final chunks = <List<TextbookSourceLine>>[];
    for (final row in instructions) {
      if (chunks.isEmpty ||
          RegExp(r'^(朗读|默读|背诵|读一读|说一说|想一想|写一写|选做|小练笔)').hasMatch(row.text)) {
        chunks.add([]);
      }
      chunks.last.add(row);
    }
    for (final chunk in chunks) {
      final layout = _exerciseLayout(chunk, pages);
      final prompt = layout == null
          ? chunk.map((r) => r.text).join('\n')
          : layout.map((r) => r.map((c) => c['text']).join('\t')).join('\n');
      final sources = [
        for (final p in chunk.map((r) => r.page).toSet()) _source(p),
      ];
      final recite = prompt.contains('背诵');
      final ranges = <Map<String, dynamic>>[];
      if (recite && paragraphs.isNotEmpty) {
        if (RegExp(r'背诵(?:课文|全文)(?:[。！.!\s]|$)').hasMatch(prompt)) {
          for (final p in paragraphs) {
            ranges.add(_range(p as Map<String, dynamic>));
          }
        } else {
          final match = RegExp(
            r'背诵(?:课文的?)?第\s*([一二三四五六七八九十\d]+)\s*(?:[～~—\-至到、和]\s*第?\s*([一二三四五六七八九十\d]+)\s*)?自然段',
          ).firstMatch(prompt);
          final number = match == null ? null : _number(match[1]!);
          final end = match?[2] == null ? number : _number(match![2]!);
          if (number != null &&
              end != null &&
              number >= 1 &&
              end >= number &&
              end <= paragraphs.length) {
            for (var i = number; i <= end; i++) {
              ranges.add(_range(paragraphs[i - 1] as Map<String, dynamic>));
            }
          }
        }
      }
      final anchor =
          '${plan.id}-i-${chunk.first.page}-${chunk.first.glyphs.first.index}';
      if (ranges.isNotEmpty) {
        (raw['recitations'] as List).add({
          'id': '$anchor-rec',
          'instruction': prompt,
          'ranges': ranges,
          'sources': sources,
          'review': newTextbookReview(),
        });
      } else if (recite) {
        candidates.add(
          TextbookDraftCandidate(
            id: '$anchor-rec',
            text: prompt,
            reason: '背诵要求尚未绑定可靠的段落范围',
            pages: chunk.map((r) => r.page).toSet().toList(),
            category: 'recitations',
          ),
        );
      }
      (raw['exercises'] as List).add({
        'id': '$anchor-ex',
        'prompt': prompt,
        if (layout != null) 'promptLayout': layout,
        'origin': 'textbook',
        'answerType': 'none',
        'answers': <String>[],
        'answerOrigin': 'none',
        'answerSources': <dynamic>[],
        'sources': sources,
        'review': newTextbookReview(),
      });
    }
    final lastBodyPage =
        analysis.paragraphs.lastOrNull?.lines.last.page ?? plan.endPage;
    raw['sources'] = [
      for (final p in pages.where((p) => p.page <= lastBodyPage))
        _source(
          p.page,
          printed: plan.printedPage == null
              ? null
              : plan.printedPage! + p.page - plan.startPage,
          status: p.status,
        ),
    ];
    return TextbookParsedLesson(
      raw,
      candidates,
      sourceAnchored: analysis.hasTitle,
    );
  }

  List<List<Map<String, dynamic>>>? _exerciseLayout(
    List<TextbookSourceLine> chunk,
    List<TextbookPageText> pages,
  ) {
    if (!RegExp(r'^(读一读|读读)').hasMatch(chunk.first.text)) return null;
    final rows = <List<TextbookSourceLine>>[];
    for (final row in chunk) {
      final widths = row.glyphs
          .where((g) => _reading.hasHan(g.text))
          .map((g) => g.width)
          .toList()
        ..sort();
      final width =
          widths.isEmpty ? double.infinity : widths[widths.length ~/ 2];
      final cells = <TextbookSourceLine>[];
      for (final glyph in row.glyphs) {
        if (cells.isEmpty ||
            glyph.left - cells.last.glyphs.last.right > width * 1.5) {
          cells.add(TextbookSourceLine(row.page, [], row.original));
        }
        cells.last.glyphs.add(glyph);
      }
      rows.add(cells);
    }
    if (!rows.any((r) => r.length > 1)) return null;
    final gridRight = rows
        .where((r) => r.length > 1)
        .expand((r) => r)
        .expand((c) => c.glyphs)
        .map((g) => g.right)
        .reduce(math.max);
    final notes = <TextbookSourceLine>[];
    final content = <List<TextbookSourceLine>>[];
    for (final row in rows) {
      // 旁注位于词组区域右侧；放在词组之后，避免插断同一题的两行内容。
      if (row.length == 1 && row.single.left > gridRight) {
        notes.add(row.single);
      } else {
        content.add(row);
      }
    }
    final marked = chunk.first.text.contains('加点');
    Map<String, dynamic> cell(TextbookSourceLine line) {
      final text = line.text;
      final runes = text.runes.toList();
      final emphasis = <int>[];
      var at = 0;
      for (final glyph in line.glyphs) {
        while (at < runes.length && runes[at] != glyph.text.runes.single) {
          at++;
        }
        final dots = pages.firstWhere((p) => p.page == line.page).glyphs;
        if (marked &&
            _reading.hasHan(glyph.text) &&
            dots.any(
              (dot) =>
                  const ['3', '·', '•', '‧', '.'].contains(dot.text) &&
                  dot.width < glyph.width * .5 &&
                  dot.height < glyph.height * .5 &&
                  (dot.centerX - glyph.centerX).abs() < glyph.width * .35 &&
                  dot.top >= glyph.bottom &&
                  dot.top - glyph.bottom < glyph.height * .6,
            )) {
          emphasis.add(at);
        }
        at++;
      }
      return {'text': text, 'emphasis': emphasis};
    }

    return [
      for (final row in content) [for (final line in row) cell(line)],
      if (notes.isNotEmpty)
        [
          {'text': notes.map((l) => l.text).join(), 'emphasis': <int>[]},
        ],
    ];
  }

  Map<String, dynamic> _range(Map<String, dynamic> p) => {
        'paragraphId': p['id'],
        'start': 0,
        'end': (p['text'] as String).runes.length,
        'textSha256': textbookTextDigest(p['text'] as String),
      };
  int? _number(String text) {
    final value = int.tryParse(text);
    if (value != null) return value;
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (!text.contains('十')) return digits[text];
    final parts = text.split('十');
    if (parts.length != 2) return null;
    final tens = parts.first.isEmpty ? 1 : digits[parts.first];
    final ones = parts.last.isEmpty ? 0 : digits[parts.last];
    return tens == null || ones == null ? null : tens * 10 + ones;
  }

  /// 册末表有独立的识字/课文分组，课号重复时必须同时匹配分组。
  Map<String, List<TextbookDraftCandidate>> vocabularyTables(
    TextbookCoursePack pack,
    List<TextbookPageText> pages,
  ) {
    final result = <String, List<TextbookDraftCandidate>>{};
    final supplementalUnits = pack.units
        .where(
          (u) => RegExp(r'古诗词诵读|习作例文|快乐读书吧').hasMatch(u.title),
        )
        .map((u) => u.id)
        .toSet();
    String? category;
    String? group;
    TextbookCourseLesson? lesson;
    for (final page in pages) {
      final heights = page.glyphs
          .where(
            (g) =>
                _reading.hasHan(g.text) &&
                g.centerX >= 0 &&
                g.centerX <= 1 &&
                g.height > 0,
          )
          .map((g) => g.height)
          .toList()
        ..sort();
      final tableHeight = heights.isEmpty ? .02 : heights[heights.length ~/ 2];
      for (final row in _reading.lines(page, table: true)) {
        final plain = _reading.plainText(row.text);
        if (RegExp(r'^识字表[①②]?$').hasMatch(plain)) {
          category = 'recognitionCharacters';
          group = null;
          lesson = null;
          continue;
        }
        if (RegExp(r'^写字表[①②]?$').hasMatch(plain)) {
          category = 'writingCharacters';
          group = null;
          lesson = null;
          continue;
        }
        if (RegExp(r'^词语表[①②]?$').hasMatch(plain)) {
          category = 'words';
          group = null;
          lesson = null;
          continue;
        }
        if (category == null) continue;
        if (RegExp(r'^[①②③④⑤⑥⑦⑧⑨]').hasMatch(plain) ||
            row.height < tableHeight * .72) {
          continue;
        }
        if (RegExp(
          r'^(?:[（(]?共\d+个|后记|附录|常用.*(?:名称|笔画|偏旁)表|笔画名称表|偏旁名称表|义务教育|责任编辑|出版)',
        ).hasMatch(plain)) {
          category = null;
          lesson = null;
          continue;
        }
        if (row.top > .95 || RegExp(r'^\d+$').hasMatch(plain)) continue;
        if (plain == '识字') {
          group = 'literacy';
          lesson = null;
          continue;
        }
        if (plain == '汉语拼音') {
          group = 'pinyin';
          lesson = null;
          continue;
        }
        if (plain == '课文' || plain == '阅读') {
          group = 'text';
          lesson = null;
          continue;
        }
        if (row.height > tableHeight * 1.8) {
          if (lesson != null && _reading.hasHan(row.text)) {
            result.putIfAbsent(lesson.id, () => []).add(
                  TextbookDraftCandidate(
                    id: '${lesson.id}-table-unclassified-${page.page}-${row.glyphs.first.index}',
                    text: row.text,
                    reason: '字表中的大字号或斜排文字，未作为字词目标',
                    pages: [page.page],
                  ),
                );
          }
          continue;
        }
        var text = row.text;
        final garden = RegExp(r'^(语文园地[一二三四五六七八九十]*)').firstMatch(plain);
        if (garden != null) {
          final matches = pack.lessons
              .where(
                (l) =>
                    _reading.titleKey(l.title) == garden[1] &&
                    (garden[1] != '语文园地' || l.unitId == lesson?.unitId),
              )
              .toList();
          lesson = matches.length == 1 ? matches.single : null;
          text = plain.substring(garden[1]!.length);
        }
        final number =
            RegExp(r'^\s*(\d{1,2})[\s.、]*(.*)$').firstMatch(row.text);
        if (number != null) {
          final matching = pack.lessons
              .where(
                (l) =>
                    l.lessonNumber == int.parse(number[1]!) &&
                    !supplementalUnits.contains(l.unitId) &&
                    (group == null ||
                        (group == 'pinyin'
                            ? !_reading.hasHan(l.title)
                            : group == 'literacy'
                                ? l.kind == 'literacy' &&
                                    _reading.hasHan(l.title)
                                : l.kind != 'literacy' &&
                                    _reading.hasHan(l.title))),
              )
              .toList();
          lesson = matching.length == 1 ? matching.single : null;
          text = number[2]!;
        }
        if (!_reading.hasHan(text)) continue;
        if (lesson == null) {
          final title = category == 'words'
              ? '词语表'
              : category == 'writingCharacters'
                  ? '写字表'
                  : '识字表';
          final appendix =
              pack.lessons.where((l) => l.title.contains(title)).firstOrNull;
          if (appendix != null) {
            result.putIfAbsent(appendix.id, () => []).add(
                  TextbookDraftCandidate(
                    id: '${appendix.id}-table-unassigned-${page.page}-${row.glyphs.first.index}',
                    text: row.text,
                    reason: '原书$title，暂未确定所属课目，请选择归属',
                    pages: [page.page],
                  ),
                );
          }
          continue;
        }
        if (category != 'words') {
          text =
              text.runes.map(String.fromCharCode).where(_reading.hasHan).join();
        }
        if (text.trim().isEmpty) continue;
        result.putIfAbsent(lesson.id, () => []).add(
              TextbookDraftCandidate(
                id: '${lesson.id}-table-${page.page}-${row.glyphs.first.index}',
                text: text,
                reason:
                    '原书${category == 'words' ? '词语表' : category == 'writingCharacters' ? '写字表' : '识字表'}，归属须核对',
                pages: [page.page],
                category: category,
              ),
            );
      }
    }
    return result;
  }
}
