import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/services/textbook_course_generation_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_progress_cleanup.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_download_controller.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_cache_manager_sheet.dart';
import 'package:poemath/features/textbook/providers/textbook_generation_controller.dart';

import '../../helpers/textbook_fixture.dart';

class _FakeFiles extends TextbookFileService {
  _FakeFiles(this.usage, {void Function(String)? onAction})
      : _onAction = onAction;

  final void Function(String)? _onAction;
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

  @override
  Future<void> removePdf(String id) async {
    _onAction?.call('files');
    courseGone = true;
  }
}

class _FakeCourses extends TextbookCourseRepository {
  _FakeCourses(this.onClear, {void Function(String)? onAction})
      : _onAction = onAction;

  final void Function() onClear;
  final void Function(String)? _onAction;
  int cleared = 0;

  @override
  Future<void> clear(Textbook book) async {
    cleared++;
    _onAction?.call('course');
    onClear();
  }
}

/// 构造期惰性 box：仅用于绕开超类对 HiveBoxes.settings 的访问，
/// 测试中从不调用其成员。
class _UnusedBox implements Box<dynamic> {
  const _UnusedBox();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试不应访问 box: ${invocation.memberName}');
}

class _FakeRepo extends TextbookRepository {
  _FakeRepo({void Function(String)? onAction})
      : _onAction = onAction,
        super(box: const _UnusedBox());
  final void Function(String)? _onAction;
  final deleted = <String>[];

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _onAction?.call('repo');
  }
}

class _FakeCleanup extends TextbookProgressCleanup {
  _FakeCleanup({void Function(String)? onAction})
      : _onAction = onAction,
        super(box: const _UnusedBox());
  final void Function(String)? _onAction;
  final deleted = <String>[];

  @override
  Future<int> deleteBookProgress(String bookId) async {
    deleted.add(bookId);
    _onAction?.call('progress');
    return 1;
  }
}

/// 构造即置入下载中状态，用于验证删除按钮被禁用。
class _SeededDownloads extends TextbookDownloadController {
  _SeededDownloads(
    TextbookFileService files,
    TextbookRepository repo,
    String id,
  ) : super(files, repo, (_) {}) {
    state = {
      id: const TextbookDownloadState(
        TextbookDownloadStatus.downloading,
        progress: 0.5,
      ),
    };
  }
}

void main() {
  final book = textbookFixture();
  const usage = TextbookStorageUsage(
    pdfBytes: 12 * 1024 * 1024,
    coverBytes: 800,
    contentBytes: 3000,
    contentFiles: 7,
    audioBytes: 2048,
    audioFiles: 2,
    courseBytes: 1024,
  );
  late _FakeFiles files;
  late _FakeCourses courses;

  Future<void> pump(
    WidgetTester tester, {
    List<Override> overrides = const [],
    void Function(String)? onAction,
  }) async {
    files = _FakeFiles(usage, onAction: onAction);
    courses = _FakeCourses(() => files.courseGone = true, onAction: onAction);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookFileServiceProvider.overrideWithValue(files),
          textbookCourseRepositoryProvider.overrideWithValue(courses),
          // 默认空状态，避免测试环境初始化 Hive。
          textbookGenerationProvider.overrideWith((ref) {
            return TextbookGenerationController(
              ref.watch(textbookGenerationServiceProvider),
              (_) {},
            );
          }),
          textbookDownloadsProvider.overrideWith((ref) {
            return TextbookDownloadController(files, _FakeRepo(), (_) {});
          }),
          ...overrides,
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

  testWidgets('删除本书按钮位于底部、错误色，确认前列出范围且不删除', (tester) async {
    await pump(tester);

    final deleteButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('cache-delete-book')),
    );
    expect(find.text('删除本书'), findsOneWidget);
    expect(deleteButton.onPressed, isNotNull);
    // 与「清理全部缓存」同行展示。
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('cache-delete-book'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('cache-clear-all'))).dy,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('cache-delete-book')))
          .left,
      greaterThan(
        tester
            .getRect(find.byKey(const ValueKey('cache-clear-all')))
            .center
            .dx,
      ),
    );
    // 确认对话框列出删除范围。
    await tester.ensureVisible(find.byKey(const ValueKey('cache-delete-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cache-delete-book')));
    await tester.pumpAndSettle();
    expect(find.text('删除本书？'), findsOneWidget);
    expect(find.textContaining('学习进度删除后不可恢复'), findsOneWidget);
    expect(find.textContaining('书目登记'), findsOneWidget);
    // 默认取消：取消后无任何数据被删。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(files.cleared, isEmpty);
    expect(courses.cleared, 0);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('确认删除本书后按序清理各仓储并关闭 sheet', (tester) async {
    final calls = <String>[];
    final repo = _FakeRepo(onAction: calls.add);
    final progress = _FakeCleanup(onAction: calls.add);
    await pump(
      tester,
      overrides: [
        textbookRepositoryProvider.overrideWithValue(repo),
        textbookProgressCleanupProvider.overrideWithValue(progress),
      ],
      onAction: calls.add,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('cache-delete-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cache-delete-book')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除本书'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      calls,
      ['progress', 'course', 'files', 'repo'],
      reason: '书目登记最后删除，中途失败不产生幽灵书',
    );
    expect(progress.deleted, [book.pdfSha256]);
    expect(courses.cleared, 1);
    expect(repo.deleted, [book.pdfSha256]);
    expect(
      find.byKey(const ValueKey('textbook-cache-sheet')),
      findsNothing,
      reason: '删除成功后 sheet 关闭',
    );

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('课程整理运行中禁止删除本书', (tester) async {
    final repo = _FakeRepo();
    final progress = _FakeCleanup();
    final generation = textbookGenerationProvider.overrideWith((ref) {
      final controller = TextbookGenerationController(
        ref.watch(textbookGenerationServiceProvider),
        (_) {},
      );
      controller.state = {
        book.pdfSha256:
            const TextbookGenerationProgress('running', 1, 3, '整理中'),
      };
      return controller;
    });
    await pump(
      tester,
      overrides: [
        textbookRepositoryProvider.overrideWithValue(repo),
        textbookProgressCleanupProvider.overrideWithValue(progress),
        generation,
      ],
    );

    final deleteButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('cache-delete-book')),
    );
    expect(deleteButton.onPressed, isNull, reason: '生成中按钮置灰');
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(const ValueKey('cache-delete-book')),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      '课程整理进行中，请稍后再试',
    );
    // 未确认时无任何数据被删。
    expect(progress.deleted, isEmpty);
    expect(repo.deleted, isEmpty);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('下载进行中禁止删除本书', (tester) async {
    final repo = _FakeRepo();
    final progress = _FakeCleanup();
    await pump(
      tester,
      overrides: [
        textbookRepositoryProvider.overrideWithValue(repo),
        textbookProgressCleanupProvider.overrideWithValue(progress),
        textbookDownloadsProvider.overrideWith((ref) {
          final controller = _SeededDownloads(files, repo, book.pdfSha256);
          return controller;
        }),
      ],
    );

    final deleteButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('cache-delete-book')),
    );
    expect(deleteButton.onPressed, isNull, reason: '下载中按钮置灰');
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(const ValueKey('cache-delete-book')),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      '下载进行中，请稍后再试',
    );
    expect(progress.deleted, isEmpty);
    expect(repo.deleted, isEmpty);

    await tester.pump(const Duration(seconds: 5));
  });
}
