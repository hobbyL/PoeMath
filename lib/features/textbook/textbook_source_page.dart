import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

/// 审核专用原页查看器，不写孩子的续读或学习记录。
class TextbookCourseSourcePage extends ConsumerStatefulWidget {
  const TextbookCourseSourcePage({
    super.key,
    required this.book,
    required this.sources,
    this.viewerBuilder,
  });
  final Textbook book;
  final List<TextbookSourcePage> sources;
  final TextbookViewerBuilder? viewerBuilder;

  @override
  ConsumerState<TextbookCourseSourcePage> createState() =>
      _TextbookSourcePageState();
}

class _TextbookSourcePageState extends ConsumerState<TextbookCourseSourcePage> {
  late int _page = widget.sources.first.pdfPage;
  TextbookGoToPage? _goTo;
  int _revision = 0;
  bool _busy = false;

  Future<void> _jump(int page) async {
    if (_goTo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _goTo!(page);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('原书跳页失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('对照原书')),
        body: ref.watch(textbookPathProvider(widget.book.pdfSha256)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: TextButton(
                  onPressed: () => ref
                      .invalidate(textbookPathProvider(widget.book.pdfSha256)),
                  child: const Text('文件检查失败，点击重试'),
                ),
              ),
              data: (path) {
                if (path == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(SpacingTokens.lg),
                      child: Text('本地原书已移除，请重新下载或导入后对照。审核草稿已保留。'),
                    ),
                  );
                }
                final revision = _revision;
                final options = TextbookViewerOptions(
                  path: path,
                  initialPage: _page,
                  onPageChanged: (page) {
                    if (mounted && revision == _revision) {
                      setState(() => _page = page);
                    }
                  },
                  onReady: (goTo) {
                    if (mounted && revision == _revision) {
                      setState(() => _goTo = goTo);
                    }
                  },
                  onRetry: () => setState(() {
                    _goTo = null;
                    _revision++;
                  }),
                );
                return KeyedSubtree(
                  key: ValueKey(_revision),
                  child: widget.viewerBuilder?.call(context, options) ??
                      TextbookPdfView(options: options),
                );
              },
            ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text('第 $_page / ${widget.book.pageCount} 页'),
                  const SizedBox(width: SpacingTokens.md),
                  for (final page
                      in widget.sources.map((source) => source.pdfPage).toSet())
                    TextButton(
                      onPressed:
                          _goTo == null || _busy ? null : () => _jump(page),
                      child: Text('来源第 $page 页'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
