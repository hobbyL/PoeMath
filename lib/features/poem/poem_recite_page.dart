// lib/features/poem/poem_recite_page.dart
//
// 背诵练习页：首字提示 → 半隐 → 全隐 → 默写 四级递进。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

/// 背诵难度级别。
enum ReciteLevel {
  firstChar('首字提示', 1),
  halfHidden('半隐模式', 2),
  allHidden('全隐模式', 3),
  dictation('默写模式', 4);

  const ReciteLevel(this.label, this.value);
  final String label;
  final int value;
}

class PoemRecitePage extends ConsumerStatefulWidget {
  const PoemRecitePage({super.key, required this.poemId});

  final String poemId;

  @override
  ConsumerState<PoemRecitePage> createState() => _PoemRecitePageState();
}

class _PoemRecitePageState extends ConsumerState<PoemRecitePage> {
  ReciteLevel _level = ReciteLevel.firstChar;
  bool _showAnswer = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poem = ref.watch(poemByIdProvider(widget.poemId));
    final theme = Theme.of(context);

    if (poem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('背诵练习')),
        body: const Center(child: Text('诗词未找到')),
      );
    }

    final lines = poem.content.split('\n').where((l) => l.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('背诵 · ${poem.title}'),
        actions: [
          PopupMenuButton<ReciteLevel>(
            initialValue: _level,
            onSelected: (level) => setState(() {
              _level = level;
              _showAnswer = false;
            }),
            itemBuilder: (context) => ReciteLevel.values
                .map(
                  (l) => PopupMenuItem(
                    value: l,
                    child: Text(l.label),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _level.label,
                    style: theme.textTheme.labelLarge,
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          children: [
            // 诗人信息
            Text(
              '〔${poem.dynasty}〕${poem.author}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),

            // 主体内容区
            Expanded(
              child: _level == ReciteLevel.dictation
                  ? _buildDictation(context, lines)
                  : _buildReciteContent(context, lines),
            ),

            // 操作按钮
            const SizedBox(height: SpacingTokens.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _showAnswer = !_showAnswer);
                    },
                    icon: Icon(
                      _showAnswer ? Icons.visibility_off : Icons.visibility,
                    ),
                    label: Text(_showAnswer ? '隐藏答案' : '显示答案'),
                  ),
                ),
                const SizedBox(width: SpacingTokens.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final progressRepo =
                          ref.read(poemProgressRepoProvider);
                      await progressRepo.recordStudy(widget.poemId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('学习已记录 ✓'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('完成背诵'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReciteContent(BuildContext context, List<String> lines) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Center(
        child: Column(
          children: lines.map((line) {
            final processed = _processLine(line);
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: SpacingTokens.sm,
              ),
              child: Text(
                _showAnswer ? line : processed,
                style: theme.textTheme.headlineSmall?.copyWith(
                  height: 2,
                  letterSpacing: 2,
                  color: _showAnswer
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDictation(BuildContext context, List<String> lines) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '请默写全文',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Expanded(
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: '在此默写…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 2,
              letterSpacing: 1,
            ),
          ),
        ),
        if (_showAnswer) ...[
          const SizedBox(height: SpacingTokens.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SpacingTokens.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.primary),
            ),
            child: Text(
              lines.join('\n'),
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 2,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  /// 根据级别处理每行文本。
  String _processLine(String line) {
    if (line.isEmpty) return line;
    final chars = line.characters.toList();

    switch (_level) {
      case ReciteLevel.firstChar:
        // 只显示首字
        return chars[0] + '＿' * (chars.length - 1);
      case ReciteLevel.halfHidden:
        // 隔一个显示一个
        final buf = StringBuffer();
        for (var i = 0; i < chars.length; i++) {
          buf.write(i.isEven ? chars[i] : '＿');
        }
        return buf.toString();
      case ReciteLevel.allHidden:
        // 全部隐藏
        return '＿' * chars.length;
      case ReciteLevel.dictation:
        return '';
    }
  }
}
