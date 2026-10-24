import 'dart:async';

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/textbook/widgets/textbook_text_search.dart';

class TextbookSearchDialog extends StatefulWidget {
  const TextbookSearchDialog({
    super.key,
    required this.search,
    required this.pageCount,
  });

  final TextbookSearch search;
  final int pageCount;

  @override
  State<TextbookSearchDialog> createState() => _TextbookSearchDialogState();
}

class _TextbookSearchDialogState extends State<TextbookSearchDialog> {
  final _input = TextEditingController();
  final _results = <TextbookSearchPage>[];
  StreamSubscription<TextbookSearchPage>? _subscription;
  int _generation = 0;
  int _searched = 0;
  int _textPages = 0;
  bool _started = false;
  bool _searching = false;
  bool _failed = false;

  void _cancel() {
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _changed(String _) {
    _cancel();
    setState(() {
      _results.clear();
      _started = false;
      _searching = false;
      _failed = false;
    });
  }

  void _submit() {
    final query = _input.text.trim();
    if (query.isEmpty) return;
    _cancel();
    final generation = _generation;
    FocusScope.of(context).unfocus();
    setState(() {
      _results.clear();
      _searched = 0;
      _textPages = 0;
      _started = true;
      _searching = true;
      _failed = false;
    });
    try {
      _subscription = widget.search(query).listen(
        (result) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _searched = result.page;
            if (result.hasText) _textPages++;
            if (result.matchCount > 0) _results.add(result);
          });
        },
        onDone: () {
          if (mounted && generation == _generation) {
            setState(() => _searching = false);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (mounted && generation == _generation) {
            setState(() {
              _searching = false;
              _failed = true;
            });
          }
        },
        cancelOnError: true,
      );
    } on Object {
      setState(() {
        _searching = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _failed
        ? '搜索未完成，请重试'
        : _searching
            ? '正在搜索 $_searched / ${widget.pageCount} 页'
            : !_started
                ? null
                : _textPages == 0
                    ? '这本书暂无可搜索的文字'
                    : _results.isEmpty
                        ? '未找到相关内容'
                        : null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ResponsiveLayout.mediumBreakpoint,
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: CustomScrollView(
            shrinkWrap: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _input,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _changed,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText:
                            _started ? '搜索关键词 ${_results.length} 条' : '搜索关键词',
                        hintText: '课文名、词语或句子',
                        suffixIcon: IconButton(
                          tooltip: '开始搜索',
                          onPressed: _submit,
                          icon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: SpacingTokens.md),
                      Text(status, style: theme.textTheme.bodyMedium),
                    ],
                    if (_searching) ...[
                      const SizedBox(height: SpacingTokens.sm),
                      LinearProgressIndicator(
                        value: _searched / widget.pageCount,
                      ),
                    ],
                    if (_failed)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _submit,
                          child: const Text('重试'),
                        ),
                      ),
                  ],
                ),
              ),
              if (_results.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: SpacingTokens.md),
                  sliver: SliverList.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: SpacingTokens.sm),
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return AppTile(
                        key: ValueKey('textbook-search-result-${result.page}'),
                        iconColor: theme.colorScheme.primary,
                        title: '第 ${result.page} 页 · ${result.matchCount} 处',
                        subtitle: result.snippet,
                        subtitleMaxLines: 2,
                        trailingInTitle: true,
                        onTap: () => Navigator.pop(context, result.page),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
