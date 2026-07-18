// lib/features/poem/poem_detail_page.dart
//
// 诗词详情页：展示全文、拼音、译文、赏析、注释，可收藏、TTS朗读和开始背诵。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_author_bios.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

/// 拼音显隐状态 Provider（读取 SettingsRepository 的持久化值）。
final _pinyinVisibleProvider = StateProvider<bool>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return settings.pinyinVisible;
});

class PoemDetailPage extends ConsumerStatefulWidget {
  const PoemDetailPage({super.key, required this.poemId});

  final String poemId;

  @override
  ConsumerState<PoemDetailPage> createState() => _PoemDetailPageState();
}

class _PoemDetailPageState extends ConsumerState<PoemDetailPage> {
  bool _isSpeaking = false;

  /// 当前正在朗读的行索引，-1 表示未朗读。
  int _currentLineIndex = -1;

  @override
  void dispose() {
    // 退出页面时停止朗读
    ref.read(ttsServiceProvider).stop();
    super.dispose();
  }

  /// 将诗词内容按换行拆分成行（去空行）。
  List<String> _splitLines(String content) {
    return content
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _toggleTts(Poem poem) async {
    final tts = ref.read(ttsServiceProvider);
    if (_isSpeaking) {
      await tts.stop();
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _currentLineIndex = -1;
        });
      }
    } else {
      final lines = _splitLines(poem.content);
      setState(() => _isSpeaking = true);
      await tts.speakLines(
        lines,
        onLineStart: (index) {
          if (mounted) {
            setState(() => _currentLineIndex = index);
          }
        },
        onComplete: () {
          if (mounted) {
            setState(() {
              _isSpeaking = false;
              _currentLineIndex = -1;
            });
          }
        },
      );
    }
  }

  Future<void> _togglePinyin() async {
    final current = ref.read(_pinyinVisibleProvider);
    final newValue = !current;
    ref.read(_pinyinVisibleProvider.notifier).state = newValue;
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setPinyinVisible(newValue);
  }

  Future<void> _sharePoem(Poem poem) async {
    final text = '《${poem.title}》\n'
        '${poem.author}·${poem.dynasty}\n'
        '\n'
        '${poem.content}\n'
        '\n'
        '—— 来自韵算 PoeMath';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final poem = ref.watch(poemByIdProvider(widget.poemId));
    final isFav = ref.watch(isFavoriteProvider(widget.poemId));
    final progress = ref.watch(poemProgressProvider(widget.poemId));
    final pinyinVisible = ref.watch(_pinyinVisibleProvider);
    final theme = Theme.of(context);

    if (poem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('诗词详情')),
        body: const Center(child: Text('诗词未找到')),
      );
    }

    // 查找作者简介
    final authorBio = poemAuthorBios[poem.author];

    return Scaffold(
      appBar: AppBar(
        title: Text(poem.title),
        actions: [
          // TTS 朗读按钮
          IconButton(
            icon: Icon(
              _isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up,
              color: _isSpeaking ? theme.colorScheme.secondary : null,
            ),
            tooltip: _isSpeaking ? '停止朗读' : '朗读全文',
            onPressed: () => _toggleTts(poem),
          ),
          // 拼音显隐切换
          if (poem.pinyin.isNotEmpty)
            IconButton(
              icon: Icon(
                pinyinVisible ? Icons.text_fields : Icons.text_fields_outlined,
                color: pinyinVisible ? theme.colorScheme.primary : null,
              ),
              tooltip: pinyinVisible ? '隐藏拼音' : '显示拼音',
              onPressed: _togglePinyin,
            ),
          // 收藏按钮（带弹跳动画）
          AnimatedFavoriteButton(
            isFavorite: isFav,
            onToggle: () async {
              final repo = ref.read(poemFavoriteRepoProvider);
              await repo.toggle(widget.poemId);
              ref.invalidate(isFavoriteProvider(widget.poemId));
            },
          ),
        ],
      ),
      body: AnimatedPageBody(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        children: [
          // 标题区
          Center(
            child: Column(
              children: [
                Text(
                  poem.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  '〔${poem.dynasty}〕${poem.author}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),

          // 正文（逐行显示，朗读时当前行高亮）
          _buildSection(
            context,
            child: Center(
              child: _buildContentLines(poem, theme),
            ),
          ),

          // 拼音（根据开关控制显隐，不折叠）
          if (poem.pinyin.isNotEmpty && pinyinVisible) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildLabeledSection(context, '拼音', poem.pinyin),
          ],

          // === 折叠区块 ===

          // 译文
          if (poem.translation.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildCollapsibleSection(
              context,
              icon: Icons.translate,
              title: '译文',
              child: Text(
                poem.translation,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
              ),
            ),
          ],

          // 注释
          if (poem.annotations.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildCollapsibleAnnotations(context, poem),
          ],

          // 赏析
          if (poem.appreciation.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildCollapsibleSection(
              context,
              icon: Icons.local_florist_outlined,
              title: '赏析',
              child: Text(
                poem.appreciation,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
              ),
            ),
          ],

          // 背景
          if (poem.background.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildCollapsibleSection(
              context,
              icon: Icons.history_edu_outlined,
              title: '创作背景',
              child: Text(
                poem.background,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
              ),
            ),
          ],

          // 名句
          if (poem.famousLines.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildCollapsibleFamousLines(context, poem.famousLines),
          ],

          // 作者简介
          if (authorBio != null) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildCollapsibleSection(
              context,
              icon: Icons.person_outline,
              title: '作者简介',
              child: Text(
                authorBio,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
              ),
            ),
          ],

          // 学习状态
          if (progress != null) ...[
            const SizedBox(height: SpacingTokens.md),
            _buildProgressInfo(context, progress.studyCount),
          ],

          const SizedBox(height: SpacingTokens.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    context.push(
                      AppRoutes.poemReciteModeOf(widget.poemId),
                    );
                  },
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('学习'),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.push(
                      AppRoutes.poemReadAlongOf(widget.poemId),
                    );
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text('跟读'),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sharePoem(poem),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('分享'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 逐行构建诗词正文，朗读时高亮当前行。
  Widget _buildContentLines(Poem poem, ThemeData theme) {
    final lines = _splitLines(poem.content);
    final poemExt = theme.extension<PoemThemeExt>();
    final baseStyle = poemExt?.poemContent ??
        theme.textTheme.bodyLarge?.copyWith(
          height: 2,
          letterSpacing: 1.5,
        );

    return Column(
      children: List.generate(lines.length, (i) {
        final isActive = _isSpeaking && i == _currentLineIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          ),
          child: Text(
            lines[i],
            style: isActive
                ? baseStyle?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  )
                : baseStyle,
            textAlign: TextAlign.center,
          ),
        );
      }),
    );
  }

  Widget _buildSection(BuildContext context, {required Widget child}) {
    return ColoredCard(
      color: Theme.of(context).colorScheme.primary,
      backgroundOpacity: 0.06,
      width: double.infinity,
      child: child,
    );
  }

  Widget _buildLabeledSection(
    BuildContext context,
    String label,
    String content,
  ) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
          ),
        ],
      ),
    );
  }

  /// 通用折叠区块：图标 + 标题 + 可展开内容，使用 ColoredCard 包裹。
  Widget _buildCollapsibleSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return ColoredCard(
      color: theme.colorScheme.primary,
      backgroundOpacity: 0.06,
      width: double.infinity,
      padding: EdgeInsets.zero,
      child: Theme(
        // 去除 ExpansionTile 默认的分割线和边框
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
          ),
          childrenPadding: const EdgeInsets.only(
            left: SpacingTokens.md,
            right: SpacingTokens.md,
            bottom: SpacingTokens.md,
          ),
          leading: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [child],
        ),
      ),
    );
  }

  /// 注释折叠区块。
  Widget _buildCollapsibleAnnotations(BuildContext context, Poem poem) {
    final theme = Theme.of(context);
    return _buildCollapsibleSection(
      context,
      icon: Icons.edit_note,
      title: '注释',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: poem.annotations.map((ann) {
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ann.word}：',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    ann.meaning,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 名句折叠区块。
  Widget _buildCollapsibleFamousLines(
    BuildContext context,
    List<String> lines,
  ) {
    final theme = Theme.of(context);
    return _buildCollapsibleSection(
      context,
      icon: Icons.format_quote,
      title: '名句',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
            child: Row(
              children: [
                Icon(
                  Icons.format_quote,
                  size: 16,
                  color: theme.semantic.caution,
                ),
                const SizedBox(width: SpacingTokens.xs),
                Expanded(
                  child: Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProgressInfo(BuildContext context, int studyCount) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: SpacingTokens.sm),
          Text(
            '已学习 $studyCount 次',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

}
