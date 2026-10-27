import 'dart:async';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/features/textbook/widgets/textbook_toc_dialog.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_detail_page.dart';
import 'package:poemath/features/textbook/textbook_reader_page.dart';
import 'package:poemath/features/textbook/textbook_management_page.dart';
import 'package:poemath/features/textbook/textbook_shelf_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';
import 'package:poemath/features/textbook/widgets/textbook_search_dialog.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';
import '../../helpers/textbook_fixture.dart';

class _MemoryRepository implements TextbookRepository {
  final books = <String, Textbook>{};
  final readings = <String, TextbookReading>{};
  final saved = <({String profile, int page})>[];
  bool failSave = false;
  bool failMatch = false;
  @override
  List<Textbook> list() => books.values.toList();
  @override
  Textbook? find(String id) => books[id];
  @override
  Future<void> addIfAbsent(Textbook book) async =>
      books.putIfAbsent(book.pdfSha256, () => book);
  @override
  TextbookReading reading(String profileId, String id) =>
      readings['$profileId:$id'] ?? const TextbookReading();
  @override
  Future<void> savePage(String profileId, Textbook book, int page) async {
    if (failSave) throw StateError('storage unavailable');
    saved.add((profile: profileId, page: page));
    readings['$profileId:${book.pdfSha256}'] = TextbookReading(
      page: page.clamp(1, book.pageCount),
      match: reading(profileId, book.pdfSha256).match,
    );
  }

  @override
  Future<void> setMatch(
    String profileId,
    String id,
    TextbookMatch match,
  ) async {
    if (failMatch) throw StateError('storage unavailable');
    readings['$profileId:$id'] =
        TextbookReading(page: reading(profileId, id).page, match: match);
  }
}

class _Files extends TextbookFileService {
  bool installed = true;
  bool failImport = false;
  int imports = 0;
  int removes = 0;
  int downloads = 0;
  final paths = <String, String>{};
  Future<void> Function(TextbookImportToken token)? downloadAction;
  @override
  Future<void> discardPickerCopy(String sourcePath) async {}
  @override
  Future<String?> installedPath(Textbook book) async =>
      installed ? paths[book.pdfSha256] ?? '/sample.pdf' : null;
  @override
  Future<void> removePdf(String id) async {
    installed = false;
    removes++;
  }

  @override
  Future<ImportedTextbookFile> importPdf({
    required String sourcePath,
    required TextbookImportToken token,
    TextbookImportProgress? onProgress,
  }) async {
    imports++;
    if (failImport) throw const TextbookFileException('PDF 无法导入');
    onProgress?.call(25, 25);
    return ImportedTextbookFile(
      sha256: textbookFixture().pdfSha256,
      pageCount: 3,
      size: 25,
    );
  }

  @override
  int get maxFileSize => 250 * 1024 * 1024;
  @override
  Future<ImportedTextbookFile> downloadPdf({
    required TextbookCatalogEntry entry,
    required TextbookImportToken token,
    TextbookImportProgress? onProgress,
  }) async {
    downloads++;
    onProgress?.call(1, 2);
    await downloadAction?.call(token);
    installed = true;
    onProgress?.call(2, 2);
    return ImportedTextbookFile(
      sha256: entry.book.pdfSha256,
      pageCount: entry.book.pageCount,
      size: entry.book.fileSize,
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer(this.options);
  final TextbookViewerOptions options;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.options
          .onReady((page) async => widget.options.onPageChanged(page)),
    );
  }

  @override
  Widget build(BuildContext context) => const Center(child: Text('合成 PDF 渲染器'));
}

class _LifecycleViewer extends StatefulWidget {
  const _LifecycleViewer({
    required this.options,
    required this.onCreate,
    required this.onDispose,
  });

  final TextbookViewerOptions options;
  final VoidCallback onCreate;
  final VoidCallback onDispose;

  @override
  State<_LifecycleViewer> createState() => _LifecycleViewerState();
}

class _LifecycleViewerState extends State<_LifecycleViewer> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.options
          .onReady((page) async => widget.options.onPageChanged(page)),
    );
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late _MemoryRepository repo;
  late _Files files;
  final book = textbookFixture();
  setUp(() {
    repo = _MemoryRepository();
    files = _Files();
    ProfileScope.reset();
  });
  tearDown(ProfileScope.reset);
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool large = false,
    Size? size,
    List<TextbookCatalogEntry> catalog = const [],
    TextbookCoverRenderer? coverRenderer,
  }) async {
    tester.view.physicalSize = size ?? const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookRepositoryProvider.overrideWithValue(repo),
          textbookFileServiceProvider.overrideWithValue(files),
          textbookCatalogProvider.overrideWith((ref) async => catalog),
          textbookPreviewBuilderProvider.overrideWithValue(
            (_, options) => _Viewer(options),
          ),
          textbookCoverRendererProvider.overrideWithValue(
            coverRenderer ?? (_, __) async => null,
          ),
        ],
        child: MaterialApp(
          builder: large
              ? (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  )
              : null,
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final catalogEntry = TextbookCatalogEntry(
    book: book,
    downloadUrl:
        Uri.parse('https://raw.githubusercontent.com/test/books/sample.pdf'),
    sourceRepository: 'test/books',
    sourceCommit: List.filled(40, 'a').join(),
    sourcePath: 'sample.pdf',
    editionLabel: '2022课标修订',
    evidencePdfPages: const [1],
  );

  testWidgets('下载页不含提示与筛选，窄屏大字的封面卡片可下载且不提前登记', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(
      tester,
      const TextbookShelfPage(),
      large: true,
      catalog: [catalogEntry],
    );
    expect(find.text('导入本地 PDF'), findsNothing);
    expect(find.text('选一本教材，下载后离线阅读'), findsNothing);
    expect(find.text('按原书版本标注，下载前请与手中教材核对。'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.scrollUntilVisible(find.text(book.title), 200);
    expect(find.text('2022课标修订'), findsOneWidget);
    expect(find.textContaining('未下载 ·'), findsOneWidget);
    expect(repo.list(), isEmpty);
    expect(files.downloads, 0);
    await tester.ensureVisible(find.byTooltip('下载${book.volumeLabel}'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下载${book.volumeLabel}'));
    await tester.pumpAndSettle();
    expect(repo.find(book.pdfSha256)?.pdfSha256, book.pdfSha256);
    expect(files.downloads, 1);
    expect(find.textContaining('已下载 · 第 1 页'), findsOneWidget);
    final edition = tester.getRect(find.text('2022课标修订'));
    final status = tester.getRect(find.textContaining('已下载 · 第 1 页'));
    final action = tester.getRect(find.byTooltip('阅读${book.volumeLabel}'));
    final actionIcon = tester.getRect(
      find.descendant(
        of: find.byTooltip('阅读${book.volumeLabel}'),
        matching: find.byIcon(Icons.auto_stories_outlined),
      ),
    );
    final cover = tester.getRect(find.byType(AspectRatio));
    expect(edition.top - cover.bottom, 8);
    expect(status.left, edition.left);
    expect(status.top - edition.bottom, inInclusiveRange(4, 17));
    expect(action.size, const Size.square(44));
    expect(actionIcon.top, greaterThanOrEqualTo(edition.bottom + 4));
    final card = tester.getRect(
      find.byKey(
        ValueKey('textbook-download-card-${book.pdfSha256}'),
      ),
    );
    expect(card.bottom - action.bottom, closeTo(8, 0.01));
    expect(card.bottom - actionIcon.bottom, closeTo(8, 0.01));
    expect(card.bottom - status.bottom, closeTo(8, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('未下载书籍直接显示真实封面，网格先横向再换行且可滚动到最后一册', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    files.installed = false;
    final entries = await const TextbookCatalogRepository().load();
    await pump(
      tester,
      const TextbookShelfPage(),
      large: true,
      catalog: entries,
    );
    Finder card(int index) => find.byKey(
          ValueKey('textbook-download-card-${entries[index].book.pdfSha256}'),
        );
    final first = tester.getRect(card(0));
    final second = tester.getRect(card(1));
    final third = tester.getRect(card(2));
    expect(first.top, second.top);
    expect(second.left, greaterThan(first.right));
    expect(third.left, first.left);
    expect(third.top, greaterThan(first.bottom));
    final cover = tester.widget<Image>(
      find.descendant(of: card(0), matching: find.byType(Image)),
    );
    expect((cover.image as AssetImage).assetName, entries.first.coverAsset);
    final edition = tester.getRect(
      find.descendant(
        of: card(0),
        matching: find.text('2022课标修订'),
      ),
    );
    final status = tester.getRect(
      find.descendant(
        of: card(0),
        matching: find.textContaining('未下载 ·'),
      ),
    );
    final download = tester.getRect(find.byTooltip('下载一年级上册'));
    expect(first.bottom - download.bottom, closeTo(8, 0.01));
    expect(first.bottom - status.bottom, closeTo(8, 0.01));
    expect(status.top - edition.bottom, inInclusiveRange(4, 17));
    expect(repo.list(), isEmpty);
    expect(files.downloads, 0);
    await tester.scrollUntilVisible(find.byTooltip('下载六年级下册'), 300);
    expect(find.byTooltip('下载六年级下册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载卡片显示进度，取消与失败后可重试，完成后切换为阅读', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(720, 800);
    tester.view.devicePixelRatio = 1;
    files.installed = false;
    final pending = Completer<void>();
    files.downloadAction = (token) async {
      await pending.future;
      try {
        token.check();
      } on TextbookImportCancelled {
        throw const TextbookDownloadCancelled();
      }
    };
    await pump(
      tester,
      const TextbookShelfPage(),
      catalog: [catalogEntry],
      size: const Size(720, 800),
    );
    final card = tester.getRect(
      find.byKey(
        ValueKey('textbook-download-card-${book.pdfSha256}'),
      ),
    );
    final button = tester.getRect(find.byTooltip('下载${book.volumeLabel}'));
    final cover = tester.getRect(find.byType(AspectRatio));
    final edition = tester.getRect(find.text('2022课标修订'));
    final status = tester.getRect(find.textContaining('未下载 ·'));
    final icon = tester.getRect(find.byIcon(Icons.download_outlined));
    expect(card.bottom - cover.bottom, closeTo(62, 0.01));
    expect(status.top - edition.bottom, closeTo(10, 0.01));
    expect(card.bottom - status.bottom, closeTo(8, 0.01));
    expect(card.bottom - icon.bottom, closeTo(8, 0.01));
    expect(button.size, const Size.square(44));
    expect(card.bottom - button.bottom, closeTo(8, 0.01));
    await tester.tap(find.byTooltip('下载${book.volumeLabel}'));
    await tester.pump();
    expect(find.text('下载中 50%'), findsOneWidget);
    expect(repo.list(), isEmpty);
    await tester.tap(find.byTooltip('取消下载${book.volumeLabel}'));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('已取消下载'), findsOneWidget);
    expect(repo.list(), isEmpty);
    files.downloadAction =
        (_) async => throw const TextbookFileException('网络中断');
    await tester.tap(find.byTooltip('下载${book.volumeLabel}'));
    await tester.pumpAndSettle();
    expect(find.text('网络中断'), findsOneWidget);
    files.downloadAction = null;
    await tester.tap(find.byTooltip('重试下载${book.volumeLabel}'));
    await tester.pumpAndSettle();
    expect(files.downloads, 3);
    expect(find.byTooltip('阅读${book.volumeLabel}'), findsOneWidget);
    expect(repo.find(book.pdfSha256), isNotNull);
  });

  testWidgets('下载不提前登记，防重入；取消、错误后可重试且保留同版位置', (tester) async {
    final pending = Completer<void>();
    files.downloadAction = (token) async {
      await pending.future;
      try {
        token.check();
      } on TextbookImportCancelled {
        throw const TextbookDownloadCancelled();
      }
    };
    await pump(
      tester,
      TextbookDetailPage(bookId: book.pdfSha256),
      catalog: [catalogEntry],
    );
    await tester.tap(find.text('下载教材'));
    await tester.pump();
    expect(find.text('下载中 50%'), findsOneWidget);
    expect(repo.list(), isEmpty);
    await tester.scrollUntilVisible(find.text('重新下载教材'), 100);
    await tester.tap(find.text('重新下载教材'));
    await tester.pump();
    expect(files.downloads, 1);
    await tester.tap(find.text('取消下载'));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('已取消下载'), findsOneWidget);
    expect(repo.list(), isEmpty);
    files.downloadAction =
        (_) async => throw const TextbookFileException('网络中断');
    await tester.tap(find.text('重新下载教材'));
    await tester.pumpAndSettle();
    expect(find.text('网络中断'), findsOneWidget);
    expect(repo.list(), isEmpty);
    files.downloadAction = null;
    await repo.savePage('default', book, 2);
    await tester.tap(find.text('重新下载教材'));
    await tester.pumpAndSettle();
    expect(repo.find(book.pdfSha256)?.title, book.title);
    expect(find.byTooltip('原书阅读'), findsOneWidget);
    expect(find.byTooltip('移除本地 PDF'), findsOneWidget);
    expect(repo.reading('default', book.pdfSha256).page, 2);
    expect(repo.reading('other', book.pdfSha256).page, 1);
  });

  testWidgets('空书架引导右上角导入下载，取消文件选择后可继续使用', (tester) async {
    var picks = 0;
    await pump(
      tester,
      TextbookManagementPage(
        pickPdf: () async {
          picks++;
          return null;
        },
      ),
    );
    expect(find.text('暂无书籍'), findsOneWidget);
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    expect(picks, 2);
    expect(files.imports, 0);
  });

  testWidgets('导入要求填写年级学期，取消登记不写书目，失败后可重试', (tester) async {
    await pump(
      tester,
      TextbookManagementPage(
        pickPdf: () async => PlatformFile(
          name: 'sample.pdf',
          size: 25,
          path: '/sample.pdf',
        ),
      ),
    );
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入教材'));
    await tester.pumpAndSettle();
    expect(find.text('请选择年级'), findsOneWidget);
    expect(find.text('请选择学期'), findsOneWidget);
    expect(files.imports, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.list(), isEmpty);
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('三年级').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上册').last);
    await tester.pumpAndSettle();
    files.failImport = true;
    await tester.tap(find.text('导入教材'));
    await tester.pumpAndSettle();
    expect(find.text('PDF 无法导入'), findsOneWidget);
    expect(repo.list(), isEmpty);
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    expect(find.text('登记教材'), findsOneWidget);
  });

  testWidgets('导入选择期间防重入，窄屏大字不溢出', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pick = Completer<PlatformFile?>();
    var count = 0;
    await pump(
      tester,
      TextbookManagementPage(
        pickPdf: () {
          count++;
          return pick.future;
        },
      ),
      large: true,
    );
    await tester.tap(find.byTooltip('导入'));
    await tester.pump();
    await tester.tap(find.byTooltip('导入'));
    await tester.pump();
    expect(count, 1);
    pick.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('管理封面网格先横向再换行，卡片打开管理详情，下载按钮进入书架', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final books = [
      book,
      textbookFixture(id: List.filled(64, 'b').join(), title: '第二本'),
      textbookFixture(id: List.filled(64, 'c').join(), title: '第三本'),
    ];
    final covers = <String, ui.Image>{};
    await tester.runAsync(() async {
      for (var index = 0; index < books.length; index++) {
        final item = books[index];
        repo.books[item.pdfSha256] = item;
        final path = '/book-$index.pdf';
        files.paths[item.pdfSha256] = path;
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 12, 16),
          ui.Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        covers[path] = await picture.toImage(12, 16);
        picture.dispose();
      }
    });
    final router =
        createAppRouter(initialLocation: AppRoutes.textbookManagement);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookRepositoryProvider.overrideWithValue(repo),
          textbookFileServiceProvider.overrideWithValue(files),
          textbookCatalogProvider.overrideWith((ref) async => []),
          textbookPreviewBuilderProvider.overrideWithValue(
            (_, options) => _Viewer(options),
          ),
          textbookCoverRendererProvider.overrideWithValue(
            (path, _) async => covers[path],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    Finder card(Textbook item) =>
        find.byKey(ValueKey('textbook-card-${item.pdfSha256}'));
    final first = tester.getRect(card(books[0]));
    final second = tester.getRect(card(books[1]));
    final third = tester.getRect(card(books[2]));
    expect(first.top, second.top);
    expect(first.left, lessThan(second.left));
    expect(third.top, greaterThan(first.bottom));
    expect(third.left, first.left);
    expect(third.width, first.width);
    for (final item in books) {
      final image = tester.widget<RawImage>(
        find.descendant(
          of: card(item),
          matching: find.byType(RawImage),
        ),
      );
      expect(image.image, same(covers[files.paths[item.pdfSha256]]));
      expect(image.fit, BoxFit.contain);
    }
    expect(find.text('本机教材'), findsNothing);
    expect(find.textContaining('已下载教材占用'), findsNothing);
    expect(find.textContaining('教材文件与阅读位置保存在本机'), findsNothing);
    for (final item in books) {
      expect(
        find.byKey(ValueKey('textbook-cache-${item.pdfSha256}')),
        findsOneWidget,
        reason: '每本书都有独立的缓存管理入口',
      );
    }
    await tester.tap(card(books[1]));
    await tester.pumpAndSettle();
    final detail = tester.widget<TextbookDetailPage>(
      find.byType(TextbookDetailPage),
    );
    expect(detail.bookId, books[1].pdfSha256);
    expect(detail.manage, isTrue);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下载'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookShelfPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('宽屏增加封面列数，缺文件仍有书名和恢复提示', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final local =
        textbookFixture(id: List.filled(64, 'b').join(), title: '自有PDF');
    repo.books.addAll({book.pdfSha256: book, local.pdfSha256: local});
    files.installed = false;
    await pump(
      tester,
      const TextbookManagementPage(),
      catalog: [catalogEntry],
      size: const Size(1000, 800),
    );
    expect(
      tester.widget<SliverGrid>(find.byType(SliverGrid)).gridDelegate,
      isA<SliverGridDelegateWithFixedCrossAxisCount>().having(
        (value) => value.crossAxisCount,
        'columns',
        5,
      ),
    );
    expect(find.text('${book.title}\n${book.volumeLabel}'), findsOneWidget);
    expect(find.text('可重新下载'), findsOneWidget);
    expect(find.text('需重新导入'), findsOneWidget);
    expect(find.byType(TextbookPdfCover), findsNothing);
    await pump(
      tester,
      const TextbookManagementPage(),
      large: true,
      catalog: [catalogEntry],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情取消移除不删文件，确认只移除 PDF并保留原核对和阅读记录', (tester) async {
    repo.books[book.pdfSha256] = book;
    await repo.savePage('default', book, 2);
    await repo.setMatch('default', book.pdfSha256, TextbookMatch.matches);
    await pump(
      tester,
      TextbookDetailPage(bookId: book.pdfSha256, manage: true),
    );
    await tester.tap(find.byTooltip('移除本地 PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(files.removes, 0);
    await tester.tap(find.byTooltip('移除本地 PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除 PDF'));
    await tester.pumpAndSettle();
    expect(files.removes, 1);
    expect(repo.find(book.pdfSha256), book);
    expect(
      repo.reading('default', book.pdfSha256).toJson(),
      {'page': 2, 'match': 'matches'},
    );
    expect(find.text('本地 PDF 已移除或丢失。请到书籍管理重新导入同一文件，恢复阅读。'), findsOneWidget);
  });

  testWidgets('详情卡片纵向居中，底部固定带箭头按钮；翻页保存续读位置', (tester) async {
    repo.books[book.pdfSha256] = book;
    final jumps = <int>[];
    var previewTaps = 0;
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookDetailPage(
        bookId: book.pdfSha256,
        previewBuilder: (_, value) {
          options = value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => previewTaps++,
            child: const Center(child: Text('预览页面')),
          );
        },
      ),
      large: true,
    );
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);
    await tester.pumpAndSettle();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final card = find.byKey(const ValueKey('textbook-detail-preview-card'));
    expect(tester.widget(card), isA<ColoredCard>());
    expect(tester.getRect(card).center.dx, 180);
    final controls = find.byKey(const ValueKey('textbook-detail-controls'));
    final cardRect = tester.getRect(card);
    final controlsRect = tester.getRect(controls);
    final previewArea = tester.getRect(
      find.byKey(const ValueKey('textbook-detail-preview-area')),
    );
    final navigation = find.byType(AppBar);
    expect(navigation, findsOneWidget);
    expect(find.text('教材详情'), findsOneWidget);
    expect(cardRect.center.dy, closeTo(previewArea.center.dy, 0.01));
    expect(cardRect.top, greaterThan(tester.getRect(navigation).bottom));
    expect(
      find.descendant(of: navigation, matching: find.byType(BackButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navigation,
        matching: find.widgetWithIcon(IconButton, Icons.delete_outline),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byType(BackButton)).center,
      const Offset(SpacingTokens.minTapTarget / 2, kToolbarHeight / 2),
    );
    final removeRect = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(removeRect.right, 360);
    expect(removeRect.center.dy, kToolbarHeight / 2);
    expect(removeRect.width, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
    expect(removeRect.height, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
    for (final buttonRect in [
      tester.getRect(find.byType(BackButton)),
      removeRect,
    ]) {
      expect(buttonRect.overlaps(cardRect), isFalse);
      expect(
        cardRect.top - buttonRect.bottom,
        greaterThanOrEqualTo(SpacingTokens.sm),
      );
    }
    await tester.tapAt(Offset(180, cardRect.top + SpacingTokens.xs));
    await tester.pumpAndSettle();
    expect(previewTaps, 1);
    expect(controlsRect.top, greaterThanOrEqualTo(cardRect.bottom));
    expect(controlsRect.bottom, 800 - 24);
    expect(controlsRect.center.dx, cardRect.center.dx);
    final footer =
        tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar!;
    const footerLabels = ['上一页', '1 / 3', '下一页'];
    for (final label in footerLabels) {
      expect(
        find.descendant(of: find.byWidget(footer), matching: find.text(label)),
        findsOneWidget,
      );
    }
    for (var index = 1; index < footerLabels.length; index++) {
      expect(
        tester.getCenter(find.text(footerLabels[index - 1])).dx,
        lessThan(tester.getCenter(find.text(footerLabels[index])).dx),
      );
    }
    final readButton = find.byKey(const ValueKey('textbook-detail-read'));
    expect(tester.widget(readButton), isA<IconButton>());
    expect(find.byTooltip('原书阅读'), findsOneWidget);
    expect(find.text('原书'), findsNothing);
    expect(find.text('原书阅读'), findsNothing);
    expect(
      find.descendant(
        of: readButton,
        matching: find.byIcon(Icons.menu_book_outlined),
      ),
      findsOneWidget,
    );
    final readRect = tester.getRect(readButton);
    expect(readRect.width, SpacingTokens.minTapTarget);
    expect(readRect.height, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
    expect(readRect.center.dy, tester.getCenter(find.text('下一页')).dy);
    expect(readRect.left, greaterThan(tester.getRect(find.text('下一页')).right));
    final pageNumber =
        find.byKey(const ValueKey('textbook-detail-page-number'));
    expect(tester.widget<TextButton>(pageNumber).onPressed, isNull);
    expect(
      tester.getRect(find.byIcon(Icons.chevron_left)).right,
      lessThan(tester.getRect(find.text('上一页')).left),
    );
    expect(
      tester.getRect(find.byIcon(Icons.chevron_right)).left,
      greaterThan(tester.getRect(find.text('下一页')).right),
    );
    expect(find.text('与手中教材核对'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('版本信息'), findsNothing);
    expect(find.textContaining('MB'), findsNothing);
    expect(find.textContaining('${book.pageCount} 页'), findsNothing);
    expect(find.text(book.volumeLabel), findsNothing);
    expect(find.byTooltip('移除本地 PDF'), findsOneWidget);
    expect(options!.initialPage, 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, '上一页'),
          )
          .onPressed,
      isNull,
    );
    options!.onReady((page) async {
      jumps.add(page);
      options!.onPageChanged(page);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(jumps, [2]);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(tester.getRect(controls), controlsRect);
    options!.onPageChanged(3);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, '下一页'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('上一页'));
    await tester.pumpAndSettle();
    expect(jumps, [2, 2]);
    expect(repo.reading('default', book.pdfSha256).page, 2);
    final old = options!;
    old.onRetry();
    await tester.pumpAndSettle();
    old.onPageChanged(3);
    old.onReady((_) async {});
    await tester.pumpAndSettle();
    expect(options!.initialPage, 2);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '下一页'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    old.onPageChanged(1);
    expect(repo.reading('default', book.pdfSha256).page, 2);
  });

  testWidgets('详情退出重进恢复阅读位置，书籍和入页档案隔离，旧书回调失效', (tester) async {
    final bookA = Textbook.fromJson({...book.toJson(), 'pageCount': 30});
    final bookB = Textbook.fromJson({
      ...bookA.toJson(),
      'pdfSha256': List.filled(64, 'b').join(),
      'title': '另一本合成教材',
    });
    repo.books[bookA.pdfSha256] = bookA;
    repo.books[bookB.pdfSha256] = bookB;
    await repo.setMatch('default', bookA.pdfSha256, TextbookMatch.matches);
    TextbookViewerOptions? options;
    TextbookDetailPage detail(Textbook selected) => TextbookDetailPage(
          bookId: selected.pdfSha256,
          previewBuilder: (_, value) {
            options = value;
            return const SizedBox.expand();
          },
        );
    await pump(tester, detail(bookA));
    expect(options!.initialPage, 1);
    options!.onPageChanged(10);
    await tester.pumpAndSettle();
    expect(
      repo.reading('default', bookA.pdfSha256).toJson(),
      {'page': 10, 'match': 'matches'},
    );
    final oldA = options!;
    await pump(tester, detail(bookB));
    expect(options!.initialPage, 1);
    oldA.onPageChanged(20);
    options!.onPageChanged(7);
    await tester.pumpAndSettle();
    expect(repo.reading('default', bookA.pdfSha256).page, 10);
    expect(repo.reading('default', bookB.pdfSha256).page, 7);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, detail(bookA));
    expect(options!.initialPage, 10);
    expect(find.text('10 / 30'), findsOneWidget);
    ProfileScope.switchTo('other');
    options!.onPageChanged(11);
    await tester.pumpAndSettle();
    expect(repo.reading('default', bookA.pdfSha256).page, 11);
    expect(repo.reading('other', bookA.pdfSha256).page, 1);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, detail(bookA));
    expect(options!.initialPage, 1);
    options!.onPageChanged(4);
    await tester.pumpAndSettle();
    expect(repo.reading('other', bookA.pdfSha256).page, 4);
    await tester.pumpWidget(const SizedBox());
    ProfileScope.reset();
    await pump(tester, detail(bookB));
    expect(options!.initialPage, 7);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, detail(bookA));
    expect(options!.initialPage, 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情保存失败可重试，不同档案及离页旧回调不改写阅读记录', (tester) async {
    final longBook = Textbook.fromJson({...book.toJson(), 'pageCount': 30});
    repo.books[longBook.pdfSha256] = longBook;
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookDetailPage(
        bookId: longBook.pdfSha256,
        previewBuilder: (_, value) {
          options = value;
          return const SizedBox.expand();
        },
      ),
    );
    repo.failSave = true;
    options!.onPageChanged(10);
    await tester.pumpAndSettle();
    expect(find.text('阅读位置保存失败'), findsOneWidget);
    expect(repo.reading('default', longBook.pdfSha256).page, 1);
    ProfileScope.switchTo('other');
    repo.failSave = false;
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(find.text('阅读位置保存失败'), findsNothing);
    expect(repo.reading('default', longBook.pdfSha256).page, 10);
    expect(repo.reading('other', longBook.pdfSha256).page, 1);
    final old = options!;
    await tester.pumpWidget(const SizedBox());
    old.onPageChanged(20);
    await tester.pumpAndSettle();
    expect(repo.saved, [(profile: 'default', page: 10)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('原书阅读支持从预览页进入并保存于当前档案', (tester) async {
    repo.books[book.pdfSha256] = book;
    await repo.savePage('default', book, 2);
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookReaderPage(
        bookId: book.pdfSha256,
        initialPage: 3,
        viewerBuilder: (_, value) {
          options = value;
          return _Viewer(value);
        },
      ),
    );
    expect(options!.initialPage, 3);
    expect(find.text('PDF 第 3 / 3 页'), findsOneWidget);
    options!.onPageChanged(3);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repo.reading('default', book.pdfSha256).page, 3);
  });

  testWidgets('从内容审核返回时复用教材详情的 PDF 预览实例', (tester) async {
    repo.books[book.pdfSha256] = book;
    var creates = 0;
    var disposes = 0;
    final router = GoRouter(
      initialLocation: AppRoutes.textbookDetailOf(book.pdfSha256),
      routes: [
        GoRoute(
          path: AppRoutes.textbookDetail,
          builder: (_, state) => TextbookDetailPage(
            bookId: state.pathParameters['id']!,
            previewBuilder: (_, options) => _LifecycleViewer(
              options: options,
              onCreate: () => creates++,
              onDispose: () => disposes++,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.textbookReview,
          builder: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('合成内容审核')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookRepositoryProvider.overrideWithValue(repo),
          textbookFileServiceProvider.overrideWithValue(files),
          textbookCatalogProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(creates, 1);
    expect(disposes, 0);

    await tester.tap(find.byTooltip('内容审核'));
    await tester.pumpAndSettle();
    expect(find.text('合成内容审核'), findsOneWidget);
    expect(creates, 1);
    expect(disposes, 0);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(TextbookDetailPage), findsOneWidget);
    expect(creates, 1);
    expect(disposes, 0);
  });

  testWidgets('详情横屏大字卡片居中，底栏与悬浮操作固定，缺文件内容仍可滚动', (tester) async {
    repo.books[book.pdfSha256] = book;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(
      tester,
      TextbookDetailPage(bookId: book.pdfSha256),
      large: true,
    );
    tester.view.physicalSize = const Size(800, 280);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    addTearDown(tester.view.resetPadding);
    await tester.pumpAndSettle();
    final back = find.byType(BackButton);
    final remove = find.widgetWithIcon(IconButton, Icons.delete_outline);
    final backRect = tester.getRect(back);
    final removeRect = tester.getRect(remove);
    expect(backRect.center, const Offset(SpacingTokens.minTapTarget / 2, 52));
    expect(removeRect.center.dy, backRect.center.dy);
    final card = find.byKey(const ValueKey('textbook-detail-preview-card'));
    final area = tester.getRect(
      find.byKey(const ValueKey('textbook-detail-preview-area')),
    );
    expect(tester.getCenter(card).dy, closeTo(area.center.dy, 0.01));
    final controls = find.byKey(const ValueKey('textbook-detail-controls'));
    final controlsRect = tester.getRect(controls);
    expect(controlsRect.bottom, 280 - 20);
    expect(tester.getRect(card).bottom, lessThan(controlsRect.top));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(controls), controlsRect);
    expect(tester.getRect(back), backRect);
    expect(tester.getRect(remove), removeRect);
    expect(back.hitTestable(), findsOneWidget);
    expect(remove.hitTestable(), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('textbook-detail-read')),
        matching: find.byIcon(Icons.menu_book_outlined),
      ),
      findsOneWidget,
    );
    for (final label in ['上一页', '1 / 3', '下一页', '原书阅读']) {
      final button = find.ancestor(
        of: find.text(label),
        matching:
            find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      );
      final buttonRect = tester.getRect(button);
      final labelRect = tester.getRect(find.text(label));
      expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left));
      expect(labelRect.right, lessThanOrEqualTo(buttonRect.right));
      expect(labelRect.top, greaterThanOrEqualTo(buttonRect.top));
      expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
      expect(buttonRect.bottom, lessThanOrEqualTo(280));
    }
    files.installed = false;
    ProviderScope.containerOf(tester.element(find.byType(TextbookDetailPage)))
        .invalidate(textbookPathProvider(book.pdfSha256));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('textbook-detail-page-number')),
          )
          .onPressed,
      isNull,
    );
    final originalCardTop = tester.getTopLeft(card).dy;
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('打开书籍管理'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card).dy, lessThan(originalCardTop));
    expect(tester.getRect(controls), controlsRect);
    expect(tester.getRect(back), backRect);
    expect(find.text('打开书籍管理').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏按展开页翻页，切回窄屏保留当前预览页', (tester) async {
    repo.books[book.pdfSha256] = book;
    TextbookViewerOptions? options;
    var previewTaps = 0;
    await pump(
      tester,
      TextbookDetailPage(
        bookId: book.pdfSha256,
        previewBuilder: (_, value) {
          options = value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => previewTaps++,
            child: _Viewer(value),
          );
        },
      ),
    );
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(options!.doublePage, isTrue);
    expect(find.byType(AppBar), findsNothing);
    final card = tester.getRect(
      find.byKey(const ValueKey('textbook-detail-preview-card')),
    );
    expect(
      card.center.dy,
      closeTo(
        tester
            .getCenter(
              find.byKey(const ValueKey('textbook-detail-preview-area')),
            )
            .dy,
        0.01,
      ),
    );
    expect(card.width / card.height, closeTo(1.5, 0.01));
    await tester.tapAt(Offset(500, card.top + SpacingTokens.sm));
    await tester.pumpAndSettle();
    expect(previewTaps, 1);
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(options!.initialPage, 2);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '下一页'))
          .onPressed,
      isNull,
    );
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(options!.doublePage, isFalse);
    expect(options!.initialPage, 2);
    expect(find.byType(AppBar), findsOneWidget);
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey('textbook-detail-preview-card')),
          )
          .dy,
      closeTo(
        tester
            .getCenter(
              find.byKey(const ValueKey('textbook-detail-preview-area')),
            )
            .dy,
        0.01,
      ),
    );
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(options!.initialPage, 3);
    expect(repo.reading('default', book.pdfSha256).page, 3);
  });

  testWidgets('详情页码支持输入与键盘跳转、校验、取消，成功跳转保存续读', (tester) async {
    final longBook = Textbook.fromJson({...book.toJson(), 'pageCount': 127});
    repo.books[longBook.pdfSha256] = longBook;
    await repo.savePage('default', longBook, 2);
    repo.saved.clear();
    TextbookViewerOptions? options;
    final jumps = <int>[];
    final turning = Completer<void>();
    await pump(
      tester,
      TextbookDetailPage(
        bookId: longBook.pdfSha256,
        previewBuilder: (_, value) {
          options = value;
          return const SizedBox.expand();
        },
      ),
      large: true,
      size: const Size(320, 800),
    );
    options!.onReady((page) async {
      jumps.add(page);
      await turning.future;
      options!.onPageChanged(page);
    });
    await tester.pumpAndSettle();
    final pageNumber =
        find.byKey(const ValueKey('textbook-detail-page-number'));
    expect(find.text('2 / 127'), findsOneWidget);
    for (final label in ['上一页', '2 / 127', '下一页']) {
      final button = find.ancestor(
        of: find.text(label),
        matching:
            find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      );
      final buttonRect = tester.getRect(button);
      final textRect = tester.getRect(find.text(label));
      expect(textRect.left, greaterThanOrEqualTo(buttonRect.left));
      expect(textRect.right, lessThanOrEqualTo(buttonRect.right));
      expect(textRect.top, greaterThanOrEqualTo(buttonRect.top));
      expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
    }
    await tester.tap(pageNumber);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '2',
    );
    for (final invalid in ['', '0', '128', '-1', 'abc', '1.5']) {
      await tester.enterText(find.byType(TextFormField), invalid);
      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      expect(find.text('请填写有效页码'), findsOneWidget);
      expect(jumps, isEmpty);
    }
    await tester.enterText(find.byType(TextFormField), '127');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 127'), findsOneWidget);
    expect(jumps, isEmpty);
    await tester.tap(pageNumber);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '127');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(jumps, [127]);
    expect(tester.widget<TextButton>(pageNumber).onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('textbook-detail-read')),
          )
          .onPressed,
      isNull,
    );
    turning.complete();
    await tester.pumpAndSettle();
    expect(options!.initialPage, 127);
    expect(find.text('127 / 127'), findsOneWidget);
    expect(tester.widget<TextButton>(pageNumber).onPressed, isNotNull);
    await tester.tap(pageNumber);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '127',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.saved, [(profile: 'default', page: 127)]);
    expect(repo.reading('default', longBook.pdfSha256).page, 127);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情双页输入右页、同展开页跳转，切单页保留准确页码', (tester) async {
    repo.books[book.pdfSha256] = book;
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookDetailPage(
        bookId: book.pdfSha256,
        previewBuilder: (_, value) {
          options = value;
          return _Viewer(value);
        },
      ),
      size: const Size(1000, 700),
    );
    final pageNumber =
        find.byKey(const ValueKey('textbook-detail-page-number'));
    await tester.tap(pageNumber);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('2–3 / 3'), findsOneWidget);
    expect(options!.initialPage, 3);
    await tester.tap(pageNumber);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '3',
    );
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('2–3 / 3'), findsOneWidget);
    expect(options!.initialPage, 2);
    await tester.tap(pageNumber);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(options!.initialPage, 3);
    expect(repo.saved, [
      (profile: 'default', page: 3),
      (profile: 'default', page: 2),
      (profile: 'default', page: 3),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页码右侧搜索本书，选择双页右页结果保存续读且重试屏蔽旧搜索', (tester) async {
    repo.books[book.pdfSha256] = book;
    await repo.savePage('default', book, 2);
    repo.saved.clear();
    final queries = <String>[];
    final jumps = <int>[];
    final turning = Completer<void>();
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookDetailPage(
        bookId: book.pdfSha256,
        previewBuilder: (_, value) {
          options = value;
          return const SizedBox.expand();
        },
      ),
      size: const Size(411, 850),
    );
    final searchButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '搜索本书',
    );
    expect(tester.widget<IconButton>(searchButton).onPressed, isNull);
    options!.onReady((page) async {
      jumps.add(page);
      await turning.future;
      options!.onPageChanged(page);
    });
    options!.onSearchReady!((query) {
      queries.add(query);
      return searchTextbookPages(
        query: query,
        pageCount: 3,
        loadPageText: (page) async => page == 3 ? '春 chOn 晓 xiAo' : '小鸭子',
      );
    });
    await tester.pumpAndSettle();
    final pageNumber =
        find.byKey(const ValueKey('textbook-detail-page-number'));
    final searchRect = tester.getRect(searchButton);
    expect(searchRect.left, greaterThan(tester.getRect(pageNumber).right));
    expect(searchRect.right, lessThan(tester.getRect(find.text('下一页')).left));
    expect(searchRect.width, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
    expect(searchRect.height, greaterThanOrEqualTo(SpacingTokens.minTapTarget));
    expect(
      tester.getCenter(find.text('下一页')).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey('textbook-detail-read'))).dx,
      ),
    );
    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('开始搜索'));
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    await tester.enterText(find.byType(TextField), '春晓');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('找到 1 页相关内容'), findsNothing);
    expect(find.text('第 3 页 · 1 处'), findsOneWidget);
    expect(find.text('春晓'), findsWidgets);
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(find.text('原书阅读'), findsOneWidget);
    expect(find.text('原书'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('textbook-search-result-3')));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookSearchDialog), findsNothing);
    expect(jumps, [3]);
    expect(tester.widget<IconButton>(searchButton).onPressed, isNull);
    turning.complete();
    await tester.pumpAndSettle();
    expect(find.text('2–3 / 3'), findsOneWidget);
    expect(options!.initialPage, 3);
    expect(repo.saved, [(profile: 'default', page: 3)]);
    expect(repo.reading('default', book.pdfSha256).page, 3);
    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(queries, ['春晓']);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    final old = options!;
    old.onRetry();
    await tester.pumpAndSettle();
    old.onSearchReady!((_) => const Stream.empty());
    old.onReady((_) async {});
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(searchButton).onPressed, isNull);
    expect(repo.saved, [(profile: 'default', page: 3)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情目录紧邻返回右侧，旋转保留位置，跳转保存续读且重试屏蔽旧回调', (tester) async {
    repo.books[book.pdfSha256] = book;
    TextbookViewerOptions? options;
    final jumps = <int>[];
    await pump(
      tester,
      TextbookDetailPage(
        bookId: book.pdfSha256,
        previewBuilder: (_, value) {
          options = value;
          return const SizedBox.expand();
        },
      ),
    );
    final toc = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '目录',
    );
    expect(tester.widget<IconButton>(toc).onPressed, isNull);
    Stream<TextbookTocProgress> load(bool refresh) => Stream.value(
          const TextbookTocProgress(
            phase: TextbookTocPhase.ready,
            scanned: 3,
            total: 3,
            result: TextbookTocResult(
              source: TextbookTocSource.bookmarks,
              entries: [TextbookTocEntry(title: '第三页章节', page: 3)],
            ),
          ),
        );
    options!.onReady((page) async {
      jumps.add(page);
      options!.onPageChanged(page);
    });
    options!.onTocReady!(load);
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: toc, matching: find.byType(AppBar)),
      findsOneWidget,
    );
    expect(
      tester.getRect(toc).right,
      lessThanOrEqualTo(tester.getRect(find.byTooltip('移除本地 PDF')).left),
    );
    final back = tester.getRect(find.byType(BackButton));
    expect(tester.getRect(toc).left, greaterThanOrEqualTo(back.right));
    expect(
      tester.getRect(toc).center.dx - back.center.dx,
      SpacingTokens.minTapTarget,
    );
    expect(
      tester.getSize(toc).width,
      greaterThanOrEqualTo(SpacingTokens.minTapTarget),
    );
    await tester.tap(toc);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    await tester.tap(find.text('第三页章节'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookTocDrawer), findsNothing);
    expect(jumps, [3]);
    expect(find.text('2–3 / 3'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(
      tester.getRect(toc).center.dx -
          tester.getRect(find.byType(BackButton)).center.dx,
      SpacingTokens.minTapTarget,
    );
    expect(repo.saved, [(profile: 'default', page: 3)]);
    final old = options!;
    old.onRetry();
    await tester.pumpAndSettle();
    old.onReady((_) async {});
    old.onTocReady!(load);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(toc).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('原书目录跳转保存当前档案位置，重建后的旧目录回调无效', (tester) async {
    repo.books[book.pdfSha256] = book;
    ProfileScope.switchTo('toc-profile');
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookReaderPage(
        bookId: book.pdfSha256,
        viewerBuilder: (_, value) {
          options = value;
          return const SizedBox.expand();
        },
      ),
    );
    options!.onReady((page) async => options!.onPageChanged(page));
    Stream<TextbookTocProgress> load(bool refresh) => Stream.value(
          const TextbookTocProgress(
            phase: TextbookTocPhase.ready,
            scanned: 3,
            total: 3,
            result: TextbookTocResult(
              source: TextbookTocSource.bookmarks,
              entries: [TextbookTocEntry(title: '第三页章节', page: 3)],
            ),
          ),
        );
    options!.onTocReady!(load);
    await tester.pumpAndSettle();
    final toc = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '目录',
    );
    expect(
      tester.getRect(toc).center.dx -
          tester.getRect(find.byType(BackButton)).center.dx,
      SpacingTokens.minTapTarget,
    );
    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第三页章节'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.reading('toc-profile', book.pdfSha256).page, 3);
    final old = options!;
    old.onRetry();
    await tester.pumpAndSettle();
    old.onReady((_) async {});
    old.onTocReady!(load);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '目录',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('原书宽屏显示对开页码，跳到右页后切窄屏保留指定页', (tester) async {
    repo.books[book.pdfSha256] = book;
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookReaderPage(
        bookId: book.pdfSha256,
        initialPage: 3,
        viewerBuilder: (_, value) {
          options = value;
          return _Viewer(value);
        },
      ),
    );
    tester.view.physicalSize = const Size(1000, 700);
    await tester.pumpAndSettle();
    expect(options!.doublePage, isTrue);
    expect(find.text('PDF 第 2–3 / 3 页'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(options!.doublePage, isFalse);
    expect(find.text('PDF 第 3 / 3 页'), findsOneWidget);
  });

  testWidgets('阅读从保存页开始，跳页校验，晚到回调仍写进入时档案', (tester) async {
    repo.books[book.pdfSha256] = book;
    await repo.savePage('default', book, 2);
    repo.saved.clear();
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookReaderPage(
        bookId: book.pdfSha256,
        viewerBuilder: (_, value) {
          options = value;
          return _Viewer(value);
        },
      ),
    );
    expect(options!.initialPage, 2);
    expect(find.text('PDF 第 2 / 3 页'), findsOneWidget);
    await tester.tap(find.text('PDF 第 2 / 3 页'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '99');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(find.text('请填写有效页码'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '3');
    ProfileScope.switchTo('other');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repo.reading('default', book.pdfSha256).page, 3);
    expect(repo.reading('other', book.pdfSha256).page, 1);
    expect(find.text('PDF 第 3 / 3 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('阅读保存失败显示重试，成功后恢复；退出立即刷新位置', (tester) async {
    repo.books[book.pdfSha256] = book;
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookReaderPage(
        bookId: book.pdfSha256,
        viewerBuilder: (_, value) {
          options = value;
          return _Viewer(value);
        },
      ),
    );
    repo.failSave = true;
    options!.onPageChanged(2);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('阅读位置保存失败'), findsOneWidget);
    repo.failSave = false;
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(repo.reading('default', book.pdfSha256).page, 2);
    expect(find.text('阅读位置保存失败'), findsNothing);
    options!.onPageChanged(3);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repo.reading('default', book.pdfSha256).page, 3);
  });

  testWidgets('核对原书从首页开始，缺失 PDF 或身份显示可恢复提示', (tester) async {
    repo.books[book.pdfSha256] = book;
    await repo.savePage('default', book, 3);
    TextbookViewerOptions? options;
    await pump(
      tester,
      TextbookReaderPage(
        bookId: book.pdfSha256,
        firstPage: true,
        viewerBuilder: (_, value) {
          options = value;
          return _Viewer(value);
        },
      ),
    );
    expect(options!.initialPage, 1);
    await tester.pumpWidget(const SizedBox());
    files.installed = false;
    await pump(tester, TextbookReaderPage(bookId: book.pdfSha256));
    expect(find.text('本地 PDF 已移除或丢失，请重新下载或导入。'), findsOneWidget);
    expect(find.byType(_Viewer), findsNothing);
  });

  testWidgets('教材路由可直接打开，无效深链不崩溃', (tester) async {
    final router =
        createAppRouter(initialLocation: AppRoutes.textbookDetailOf('missing'));
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textbookRepositoryProvider.overrideWithValue(repo),
          textbookCatalogProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('找不到这本教材，请返回书架重新选择。'), findsOneWidget);
    router.go(AppRoutes.textbookReadOf('missing'));
    await tester.pumpAndSettle();
    expect(find.text('找不到这本教材，请回书架重新选择。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
