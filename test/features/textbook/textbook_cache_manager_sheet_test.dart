import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_cache_manager_sheet.dart';

import '../../helpers/textbook_fixture.dart';

class _FakeFiles extends TextbookFileService {
  _FakeFiles(this.usage);

  TextbookStorageUsage usage;
  final cleared = <String>[];
  bool courseGone = false;

  void _set({
    int? cover,
    int? content,
    int? contentFiles,
    int? audio,
    int? audioFiles,
  }) {
    usage = TextbookStorageUsage(
      pdfBytes: usage.pdfBytes,
      coverBytes: cover ?? usage.coverBytes,
      contentBytes: content ?? usage.contentBytes,
      contentFiles: contentFiles ?? usage.contentFiles,
      audioBytes: audio ?? usage.audioBytes,
      audioFiles: audioFiles ?? usage.audioFiles,
      courseBytes: usage.courseBytes,
    );
  }

  @override
  Future<TextbookStorageUsage> storageUsage(Textbook book) async =>
      courseGone
          ? TextbookStorageUsage(
              pdfBytes: usage.pdfBytes,
              coverBytes: usage.coverBytes,
              contentBytes: usage.contentBytes,
              contentFiles: usage.contentFiles,
              audioBytes: usage.audioBytes,
              audioFiles: usage.audioFiles,
              courseBytes: 0,
            )
          : usage;

  @override
  Future<void> clearCover(Textbook book) async {
    cleared.add('cover');
    _set(cover: 0);
  }

  @override
  Future<void> clearExtractedContent(Textbook book) async {
    cleared.add('content');
    _set(content: 0, contentFiles: 0);
  }

  @override
  Future<void> clearNarration(Textbook book) async {
    cleared.add('audio');
    _set(audio: 0, audioFiles: 0);
  }

  @override
  Future<void> clearDerived(Textbook book) async {
    cleared.add('all');
    _set(cover: 0, content: 0, contentFiles: 0, audio: 0, audioFiles: 0);
  }
}

class _FakeCourses extends TextbookCourseRepository {
  _FakeCourses(this.onClear);

  final void Function() onClear;
  int cleared = 0;

  @override
  Future<void> clear(Textbook book) async {
    cleared++;
    onClear();
  }
}

void main() {
  final book = textbookFixture();
  late _FakeFiles files;
  late _FakeCourses courses;

  setUp(() {
    files = _FakeFiles(
      const TextbookStorageUsage(
        pdfBytes: 12 * 1024 * 1024,
        coverBytes: 800,
        contentBytes: 3000,
        contentFiles: 7,
        audioBytes: 2048,
        audioFiles: 2,
        courseBytes: 1024,
      ),
    );
    courses = _FakeCourses(() => files.courseGone = true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookFileServiceProvider.overrideWithValue(files),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
        ],
        child: MaterialApp(
          home: Scaffold(body: TextbookCacheSheet(book: book)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('列出原书、封面、目录、音频与课程数据及可清理总量', (tester) async {
    await pump(tester);

    expect(find.text('缓存管理'), findsOneWidget);
    expect(find.text('可清理缓存'), findsOneWidget);
    expect(find.text('朗读音频（句子/字/词）'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('cache-derived-total')))
          .data,
      '6 KB',
      reason: '800 + 3000 + 2048 字节',
    );
    for (final key in [
      'cache-row-pdf',
      'cache-row-cover',
      'cache-row-content',
      'cache-row-audio',
      'cache-row-course',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.textContaining('12.0 MB'), findsOneWidget);
    expect(find.textContaining('7 个文件'), findsOneWidget);
    expect(find.textContaining('2 段'), findsOneWidget);
    // 原书只能查看；课程内容可删除，但必须走强确认。
    expect(find.byKey(const ValueKey('cache-delete-pdf')), findsNothing);
    expect(find.byKey(const ValueKey('cache-delete-course')), findsOneWidget);
    expect(find.byKey(const ValueKey('cache-delete-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('cache-clear-all')), findsOneWidget);
  });

  testWidgets('取消确认不清理，确认后只清理对应项', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('cache-delete-content')));
    await tester.pumpAndSettle();
    expect(find.text('清理目录与提取内容？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(files.cleared, isEmpty);

    await tester.tap(find.byKey(const ValueKey('cache-delete-content')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();

    expect(files.cleared, ['content']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cache-row-content')),
        matching: find.text('未生成'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('7 个文件'), findsNothing);
    // 其他项不受影响。
    expect(find.textContaining('2 段'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('删除课程内容需强确认，且不影响其他缓存', (tester) async {
    await pump(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('cache-delete-course')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cache-delete-course')));
    await tester.pumpAndSettle();
    expect(find.text('删除课程内容？'), findsOneWidget);
    expect(find.textContaining('不会自动恢复'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(courses.cleared, 0);

    await tester.tap(find.byKey(const ValueKey('cache-delete-course')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(courses.cleared, 1);
    expect(files.cleared, isEmpty, reason: '课程数据由仓储删除，不经文件服务');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cache-row-course')),
        matching: find.text('未生成'),
      ),
      findsOneWidget,
    );
    // 封面、目录与音频不受影响。
    expect(find.textContaining('7 个文件'), findsOneWidget);
    expect(find.textContaining('2 段'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('清理全部缓存后显示暂无缓存', (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('cache-clear-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cache-clear-all')));
    await tester.pumpAndSettle();
    expect(find.text('清理全部缓存？'), findsOneWidget);
    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();

    expect(files.cleared, ['all']);
    expect(find.text('暂无缓存'), findsOneWidget);
    expect(find.byKey(const ValueKey('cache-empty')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('cache-derived-total')))
          .data,
      '0 KB',
    );
    final clearAll = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('cache-clear-all')),
    );
    expect(clearAll.onPressed, isNull, reason: '没有缓存时不能再清理');

    await tester.pump(const Duration(seconds: 5));
  });
}
