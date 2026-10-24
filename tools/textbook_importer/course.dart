/// Run from the project root: fvm dart run tools/textbook_importer/course.dart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';

export 'package:poemath/data/models/textbook_course_review.dart'
    show newTextbookReview, reviewTextbookCourse;

const _encoder = JsonEncoder.withIndent('  ');

Map<String, dynamic> _map(Object? value, String name) {
  if (value is! Map<String, dynamic>) throw FormatException('$name 须为对象');
  return value;
}

List<dynamic> _list(Object? value, String name) {
  if (value is! List) throw FormatException('$name 须为数组');
  return value;
}

/// 只将已提取页文作为核对材料；目录仅建骨架，不推断课程要求。
Map<String, dynamic> buildTextbookCourseDraft({
  required Map<String, dynamic> extraction,
  required Map<String, dynamic> catalog,
  Map<String, dynamic>? toc,
}) {
  final source = _validateExtraction(extraction);
  final books = _catalogBooks(catalog);
  final raw =
      books.where((book) => book['sha256'] == source['sha256']).toList();
  if (raw.length != 1) throw const FormatException('抽取草稿须匹配唯一原书目录项');
  final entry = TextbookCatalogEntry.fromJson(raw.single);
  final book = entry.book;
  if (book.fileSize != source['fileSizeBytes'] ||
      book.pageCount !=
          _map(extraction['qualitySummary'], 'qualitySummary')['pageCount']) {
    throw const FormatException('草稿与原书目录的大小/页数不一致');
  }
  final draft = <String, dynamic>{
    'schemaVersion': TextbookCoursePack.schemaVersion,
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
      'publicationDate': raw.single['publicationDate'],
      'editionNumber': raw.single['editionNumber'],
      'printingDate': raw.single['printingDate'],
      'printingNumber': raw.single['printingNumber'],
      'sourceUrl': entry.downloadUrl.toString(),
      'sources': [
        for (final page in entry.evidencePdfPages)
          _sourcePage(extraction, page, null),
      ],
      'review': newTextbookReview(),
    },
    // 资源公开可达及书目核验均不审批课程内容/用途许可。
    'permissions': {
      'content': {'status': 'unknown', 'evidence': ''},
      'applicationUse': {'status': 'unknown', 'evidence': ''},
    },
    'review': newTextbookReview(),
    'units': <Map<String, dynamic>>[],
    'lessons': <Map<String, dynamic>>[],
  };
  if (toc != null) _seedToc(draft, extraction, toc);
  return TextbookCoursePack.fromJson(draft).toJson();
}

Map<String, dynamic> _validateExtraction(Map<String, dynamic> draft) {
  if (draft['schemaVersion'] != 1 ||
      draft['status'] != 'draft' ||
      draft['contentReviewStatus'] != 'unreviewed') {
    throw const FormatException('须使用页级抽取器生成的未审草稿');
  }
  final source = _map(draft['source'], 'source');
  if (source['sha256'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(source['sha256'] as String) ||
      source['fileSizeBytes'] is! int ||
      (source['fileSizeBytes'] as int) <= 0) {
    throw const FormatException('草稿PDF身份无效');
  }
  final count = _map(draft['qualitySummary'], 'qualitySummary')['pageCount'];
  final pages = _list(draft['pages'], 'pages');
  if (count is! int || count < 1 || count > 5000 || pages.length != count) {
    throw const FormatException('抽取草稿页数不完整');
  }
  for (final (index, value) in pages.indexed) {
    final page = _map(value, 'pages[$index]');
    if (page['pdfPageNumber'] != index + 1 ||
        page['text'] is! String ||
        !const [
          'text_extracted',
          'no_text',
          'low_text',
          'replacement_characters',
          'cid_placeholders',
          'extraction_error',
        ].contains(page['extractionStatus'])) {
      throw FormatException('抽取草稿第${index + 1}页缺失或格式无效');
    }
  }
  return source;
}

List<Map<String, dynamic>> _catalogBooks(Map<String, dynamic> catalog) {
  if (catalog['schemaVersion'] != 1) throw const FormatException('书目版本不支持');
  final books =
      _list(catalog['books'], 'books').map((e) => _map(e, 'book')).toList();
  final hashes = <String>{};
  final volumes = <String>{};
  for (final raw in books) {
    final entry = TextbookCatalogEntry.fromJson(raw);
    if (!hashes.add(entry.book.pdfSha256) ||
        !volumes.add('${entry.book.grade}/${entry.book.semester}')) {
      throw const FormatException('书目中存在重复PDF或册次');
    }
  }
  return books;
}

Map<String, dynamic> _sourcePage(
  Map<String, dynamic> extraction,
  int page,
  Object? printed,
) {
  final pages = extraction['pages'] as List;
  if (page < 1 || page > pages.length) throw const FormatException('目录页码越界');
  return {
    'pdfPage': page,
    'printedPage': printed?.toString(),
    'extractionStatus': (pages[page - 1] as Map)['extractionStatus'],
  };
}

void _seedToc(
  Map<String, dynamic> draft,
  Map<String, dynamic> extraction,
  Map<String, dynamic> envelope,
) {
  final edition = draft['edition'] as Map;
  if (envelope['sha256'] != edition['pdfSha256'] ||
      envelope['pageCount'] != edition['pageCount'] ||
      envelope['pdfSize'] != edition['fileSize'] ||
      envelope['version'] != 1) {
    throw const FormatException('目录缓存与课程原书身份/格式不一致');
  }
  final data = _map(envelope['data'], 'toc.data');
  if (data['tocVersion'] != 1 ||
      data['hasText'] is! bool ||
      !const ['text', 'bookmarks'].contains(data['source'])) {
    throw const FormatException('目录内容版本或来源无效');
  }
  final entries = _list(data['entries'], 'toc.entries');
  final directory = _list(data['directoryPages'], 'toc.directoryPages');
  final units = draft['units'] as List;
  final lessons = draft['lessons'] as List;
  Map<String, dynamic>? unit;
  for (final value in entries) {
    final raw = _map(value, 'toc.entry');
    if (raw['title'] is! String ||
        (raw['title'] as String).trim().isEmpty ||
        raw['isGroup'] is! bool ||
        raw['level'] is! int ||
        (raw['level'] as int) < 0) {
      throw const FormatException('目录条目格式无效');
    }
    // 保留原书次序；深层子篇作为独立待核课目，不擅自猜测正文段落关系。
    final isUnit = raw['isGroup'] == true && raw['level'] == 0;
    if (isUnit || unit == null || raw['level'] == 0) {
      final unitSources = <Map<String, dynamic>>[
        for (final page in directory)
          _sourcePage(extraction, _positivePage(page), null),
      ];
      unit = {
        'id': 'unit-${(units.length + 1).toString().padLeft(3, '0')}',
        'title': isUnit ? raw['title'] : '待核分组',
        'sources': unitSources,
        'review': newTextbookReview(),
        'lessonIds': <String>[],
      };
      units.add(unit);
    }
    if (isUnit) continue;
    final lessonId =
        'lesson-${(lessons.length + 1).toString().padLeft(3, '0')}';
    (unit['lessonIds'] as List).add(lessonId);
    lessons.add({
      'id': lessonId,
      'unitId': unit['id'],
      'title': raw['title'],
      'kind': 'other',
      'lessonNumber': raw['lessonNumber'],
      'sources': [
        if (raw['page'] != null)
          _sourcePage(
            extraction,
            _positivePage(raw['page']),
            raw['printedPage'],
          ),
      ],
      'review': newTextbookReview(),
      'coverage': {for (final c in TextbookCoursePack.categories) c: 'pending'},
      for (final category in TextbookCoursePack.categories)
        category: <Object?>[],
    });
  }
}

int _positivePage(Object? value) {
  if (value is! int || value < 1) throw const FormatException('PDF页码须为正整数');
  return value;
}

/// 审核者须显式选择节点、决定和核对项；不提供一键全书批准。
String textbookCourseWorksheet(
  TextbookCoursePack pack,
  Map<String, dynamic> extraction,
) {
  final source = _validateExtraction(extraction);
  if (source['sha256'] != pack.edition.pdfSha256 ||
      source['fileSizeBytes'] != pack.edition.fileSize ||
      (extraction['pages'] as List).length != pack.edition.pageCount) {
    throw const FormatException('核对工作表与原书身份不一致');
  }
  final out = StringBuffer('# ${pack.edition.title} · 内容审核工作表\n\n');
  out.writeln(
    '版次：${pack.edition.editionLabel}；PDF SHA-256：${pack.edition.pdfSha256}\n',
  );
  out.writeln('以下页文是抽取线索；请对照原页补齐段落/注音/字词/背诵/习题，逐项审核。\n');
  void section(TextbookCourseNode node, String title) {
    out.writeln('## $title (`${node.id}`)\n');
    out.writeln('- 审核状态：${node.review.status.name}；有效：${node.isApproved}');
    out.writeln('- 必核项：${node.requiredChecks.join('、')}\n');
    for (final source in node.sources) {
      out.writeln(
        '### PDF 第${source.pdfPage}页 · 印刷页 ${source.printedPage ?? '待核'} · ${source.extractionStatus}\n',
      );
      final page = (extraction['pages'] as List)[source.pdfPage - 1] as Map;
      // 缩进代码块保留抽取内容，不让原文中的Markdown变成工作表结构。
      for (final line in (page['text'] as String).split('\n')) {
        out.writeln('    $line');
      }
      out.writeln();
    }
  }

  section(pack.edition, '版次与来源');
  for (final unit in pack.units) {
    out.writeln('# ${unit.title}\n');
    for (final id in unit.lessonIds) {
      final lesson = pack.lessons.singleWhere((lesson) => lesson.id == id);
      section(lesson, lesson.title);
      for (final target in lesson.targets) {
        section(target, target.id);
      }
      out.writeln('覆盖：${lesson.coverage.map((k, v) => MapEntry(k, v.name))}\n');
    }
  }
  out.writeln('## 发布阻断项\n');
  for (final issue in pack.publicationIssues) {
    out.writeln('- $issue');
  }
  return out.toString();
}

Map<String, dynamic> buildTextbookReviewMatrix({
  required Map<String, dynamic> catalog,
  List<Map<String, dynamic>> extractions = const [],
  List<TextbookCoursePack> packs = const [],
}) {
  final books = _catalogBooks(catalog);
  if (books.length != 12) throw const FormatException('首期审核矩阵须覆盖小学全部12册');
  final seenDrafts = <String>{};
  final seenPacks = <String>{};
  final byHash = {for (final b in books) b['sha256'] as String: b};
  for (final draft in extractions) {
    final source = _validateExtraction(draft);
    final hash = source['sha256'] as String;
    final book = byHash[hash];
    if (!seenDrafts.add(hash) ||
        book == null ||
        source['fileSizeBytes'] != book['bytes'] ||
        (draft['pages'] as List).length != book['pageCount']) {
      throw const FormatException('抽取草稿重复或与目录原书身份不一致');
    }
  }
  for (final pack in packs) {
    final e = pack.edition;
    final book = byHash[e.pdfSha256];
    if (!seenPacks.add(e.pdfSha256) ||
        book == null ||
        e.fileSize != book['bytes'] ||
        e.pageCount != book['pageCount'] ||
        e.grade != book['grade'] ||
        e.semester != book['semester']) {
      throw const FormatException('课程包重复或与目录原书身份不一致');
    }
  }
  return {
    'schemaVersion': 1,
    'kind': 'textbookReviewMatrix',
    'books': [for (final raw in books) _matrixEntry(raw, extractions, packs)],
  };
}

Map<String, dynamic> _matrixEntry(
  Map<String, dynamic> raw,
  List<Map<String, dynamic>> drafts,
  List<TextbookCoursePack> packs,
) {
  final matches = packs.where((p) => p.edition.pdfSha256 == raw['sha256']);
  final pack = matches.isEmpty ? null : matches.single;
  final extraction =
      drafts.where((p) => (p['source'] as Map)['sha256'] == raw['sha256']);
  final draft = extraction.isEmpty ? null : extraction.single;
  final json = pack?.toJson();
  return {
    'grade': raw['grade'],
    'semester': raw['semester'],
    'title': raw['title'],
    'pdfSha256': raw['sha256'],
    'pageCount': raw['pageCount'],
    'fileSize': raw['bytes'],
    'editionLabel': raw['editionLabel'],
    'editionEvidencePdfPages': raw['evidencePdfPages'],
    'sourceUrl': raw['downloadUrl'],
    'resourceVerification': 'catalogEvidenceRecorded',
    'extraction': draft == null ? 'notRecorded' : 'draft',
    'pagesNeedingReview': draft == null
        ? null
        : (draft['qualitySummary'] as Map)['pagesNeedingReview'],
    'directory':
        pack == null || pack.lessons.isEmpty ? 'notRecorded' : 'draftOutline',
    'contentReview': pack == null
        ? 'notStarted'
        : (pack.status == 'reviewed' &&
                pack.publicationIssues.every((i) => i.code == 'permission')
            ? 'reviewed'
            : 'unreviewed'),
    'coverage': pack?.coverage ?? 'notStarted',
    'lessonCount': pack?.lessons.length ?? 0,
    'approvedTargetCount': pack?.lessons
            .expand((l) => l.targets)
            .where((t) => t.isApproved)
            .length ??
        0,
    'permissions': json?['permissions'] ??
        {
          'content': {'status': 'unknown', 'evidence': ''},
          'applicationUse': {'status': 'unknown', 'evidence': ''},
        },
    'publishable': pack?.isPublishable ?? false,
    'publicationIssues':
        pack?.publicationIssues.map((i) => i.toJson()).toList() ?? [],
  };
}

class _Options {
  _Options(List<String> args) {
    for (var i = 0; i < args.length; i++) {
      final key = args[i];
      if (!key.startsWith('--') || values.containsKey(key)) {
        throw FormatException('无效或重复参数：$key');
      }
      if (const ['--force', '--for-publish'].contains(key)) {
        values[key] = 'true';
      } else {
        if (++i >= args.length || args[i].startsWith('--')) {
          throw FormatException('参数缺少值：$key');
        }
        values[key] = args[i];
      }
    }
  }
  final values = <String, String>{};
  String require(String key) =>
      values[key] ?? (throw FormatException('缺少参数 $key'));
  void allow(List<String> names) {
    final unknown = values.keys.where((k) => !names.contains(k)).toList();
    if (unknown.isNotEmpty) throw FormatException('未知参数：${unknown.join(', ')}');
  }
}

Future<Map<String, dynamic>> _readJson(String path) async =>
    _map(jsonDecode(await File(path).readAsString()), path);

Future<void> _write(
  String destination,
  String content,
  _Options options,
  Iterable<String> inputs, {
  String extension = '.json',
}) async {
  if (!destination.toLowerCase().endsWith(extension)) {
    throw FormatException('输出须使用 $extension 扩展名');
  }
  final target = File(destination).absolute;
  for (final input in inputs) {
    final source = File(input).absolute;
    if (source.path == target.path ||
        (await target.exists() &&
            await target.resolveSymbolicLinks() ==
                await source.resolveSymbolicLinks()) ||
        (await target.exists() &&
            await FileSystemEntity.identical(source.path, target.path))) {
      throw const FormatException('输出不得覆盖输入文件');
    }
  }
  if (await target.exists() && options.values['--force'] != 'true') {
    throw const FormatException('输出已存在；如需替换请显式使用 --force');
  }
  // 临时目录内写完整文件再同文件系统rename，不留下半份JSON。
  await target.parent.create(recursive: true);
  final temporary = await target.parent.createTemp('.textbook-course-');
  try {
    final pending = File('${temporary.path}/output');
    await pending.writeAsString(content, flush: true);
    if (await target.exists() && options.values['--force'] != 'true') {
      throw const FormatException('输出已被其他写入创建');
    }
    await pending.rename(target.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<int> runTextbookCourseCommand(
  List<String> args, {
  StringSink? output,
  StringSink? errors,
}) async {
  final out = output ?? stdout;
  final err = errors ?? stderr;
  try {
    if (args.isEmpty || args.first == '--help') {
      out.writeln(
        'Textbook course: init | validate | review | worksheet | matrix | export\nSee tools/textbook_importer/COURSE_SCHEMA.md for fields and commands.',
      );
      return 0;
    }
    final options = _Options(args.skip(1).toList());
    final command = args.first;
    final common = ['--output', '--force'];
    Map<String, dynamic> result;
    final inputs = <String>[];
    Future<Map<String, dynamic>> read(String key) async {
      final path = options.require(key);
      inputs.add(path);
      return _readJson(path);
    }

    switch (command) {
      case 'init':
        options.allow(['--draft', '--catalog', '--toc', ...common]);
        final extraction = await read('--draft');
        final catalog = await read('--catalog');
        final toc =
            options.values.containsKey('--toc') ? await read('--toc') : null;
        result = buildTextbookCourseDraft(
          extraction: extraction,
          catalog: catalog,
          toc: toc,
        );
      case 'validate':
      case 'export':
        options.allow(
          ['--input', if (command == 'validate') '--for-publish', ...common],
        );
        final pack = TextbookCoursePack.fromJson(await read('--input'));
        final issues = pack.publicationIssues;
        if (command == 'export') {
          TextbookCoursePack.forPublication(pack.toJson());
          result = pack.toJson();
        } else {
          result = {
            'schemaValid': true,
            'publishable': pack.isPublishable,
            'editionId': pack.edition.id,
            'contentRevision': pack.contentRevision,
            'lessonCount': pack.lessons.length,
            'publicationIssues': issues.map((e) => e.toJson()).toList(),
          };
          if (options.values.containsKey('--output')) {
            await _write(
              options.require('--output'),
              '${_encoder.convert(result)}\n',
              options,
              inputs,
            );
          }
          out.writeln(_encoder.convert(result));
          return options.values['--for-publish'] == 'true' && issues.isNotEmpty
              ? 2
              : 0;
        }
      case 'review':
        options.allow([
          '--input',
          '--node',
          '--reviewer',
          '--decision',
          '--checks',
          '--notes',
          ...common,
        ]);
        result = reviewTextbookCourse(
          input: await read('--input'),
          nodeId: options.require('--node'),
          reviewer: options.require('--reviewer'),
          decision: options.require('--decision'),
          checks: options
              .require('--checks')
              .split(',')
              .map((s) => s.trim())
              .toList(),
          notes: options.require('--notes'),
        );
      case 'worksheet':
        options.allow(['--input', '--draft', ...common]);
        final pack = TextbookCoursePack.fromJson(await read('--input'));
        final worksheet = textbookCourseWorksheet(pack, await read('--draft'));
        await _write(
          options.require('--output'),
          worksheet,
          options,
          inputs,
          extension: '.md',
        );
        out.writeln('审核工作表：${options.require('--output')}');
        return 0;
      case 'matrix':
        options.allow(['--catalog', '--drafts', '--packs', ...common]);
        final catalog = await read('--catalog');
        Future<List<Map<String, dynamic>>> files(String key) async {
          final directory = options.values[key];
          if (directory == null) return [];
          final results = <Map<String, dynamic>>[];
          final entities = await Directory(directory).list().toList();
          entities.sort((a, b) => a.path.compareTo(b.path));
          for (final file in entities
              .whereType<File>()
              .where((f) => f.path.endsWith('.json'))) {
            inputs.add(file.path);
            results.add(await _readJson(file.path));
          }
          return results;
        }
        result = buildTextbookReviewMatrix(
          catalog: catalog,
          extractions: await files('--drafts'),
          packs: (await files('--packs'))
              .map(TextbookCoursePack.fromJson)
              .toList(),
        );
      default:
        throw FormatException('未知命令 $command');
    }
    await _write(
      options.require('--output'),
      '${_encoder.convert(result)}\n',
      options,
      inputs,
    );
    out.writeln('$command：${options.require('--output')}');
    return 0;
  } on FormatException catch (error) {
    err.writeln('课程数据校验失败：${error.message}');
    return 2;
  } on FileSystemException catch (error) {
    err.writeln('课程文件操作失败：${error.message}');
    return 2;
  } on TypeError catch (_) {
    err.writeln('课程数据校验失败：字段类型无效');
    return 2;
  }
}

Future<void> main(List<String> args) async {
  exitCode = await runTextbookCourseCommand(args);
}
