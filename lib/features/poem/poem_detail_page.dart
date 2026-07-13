// lib/features/poem/poem_detail_page.dart
//
// 诗词详情页：展示全文、拼音、译文、赏析、注释，可收藏、TTS朗读和开始背诵。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

/// TTS 服务 Provider。
final _ttsServiceProvider = Provider<TtsService>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  final service = TtsService(settings);
  ref.onDispose(service.dispose);
  return service;
});

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

  @override
  void dispose() {
    // 退出页面时停止朗读
    ref.read(_ttsServiceProvider).stop();
    super.dispose();
  }

  Future<void> _toggleTts(Poem poem) async {
    final tts = ref.read(_ttsServiceProvider);
    if (_isSpeaking) {
      await tts.stop();
      setState(() => _isSpeaking = false);
    } else {
      setState(() => _isSpeaking = true);
      await tts.speak(poem.content);
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _togglePinyin() async {
    final current = ref.read(_pinyinVisibleProvider);
    final newValue = !current;
    ref.read(_pinyinVisibleProvider.notifier).state = newValue;
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setPinyinVisible(newValue);
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
          // 收藏按钮
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? theme.colorScheme.secondary : null,
            ),
            onPressed: () async {
              final repo = ref.read(poemFavoriteRepoProvider);
              await repo.toggle(widget.poemId);
              ref.invalidate(isFavoriteProvider(widget.poemId));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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

            // 正文
            _buildSection(
              context,
              child: Center(
                child: Text(
                  poem.content,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 2,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // 拼音（根据开关控制显隐）
            if (poem.pinyin.isNotEmpty && pinyinVisible) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '拼音', poem.pinyin),
            ],

            // 译文
            if (poem.translation.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '译文', poem.translation),
            ],

            // 注释
            if (poem.annotations.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildAnnotations(context, poem),
            ],

            // 赏析
            if (poem.appreciation.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '赏析', poem.appreciation),
            ],

            // 背景
            if (poem.background.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildLabeledSection(context, '创作背景', poem.background),
            ],

            // 名句
            if (poem.famousLines.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildFamousLines(context, poem.famousLines),
            ],

            // 学习状态
            if (progress != null) ...[
              const SizedBox(height: SpacingTokens.md),
              _buildProgressInfo(context, progress.studyCount),
            ],

            const SizedBox(height: SpacingTokens.xl),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.push(AppRoutes.poemReciteOf(widget.poemId));
                  },
                  icon: const Icon(Icons.record_voice_over),
                  label: const Text('开始背诵'),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      _showQuizTypePicker(context, widget.poemId),
                  icon: const Icon(Icons.quiz_outlined),
                  label: const Text('开始测试'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      ),
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

  Widget _buildAnnotations(BuildContext context, Poem poem) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '注释',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          ...poem.annotations.map((ann) {
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
          }),
        ],
      ),
    );
  }

  Widget _buildFamousLines(BuildContext context, List<String> lines) {
    final theme = Theme.of(context);
    return _buildSection(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '名句',
            style: theme.textTheme.titleSmall?.copyWith(
              color: ColorTokens.poemGold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          ...lines.map((line) {
            return Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.format_quote,
                    size: 16,
                    color: ColorTokens.poemGold,
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
          }),
        ],
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

  void _showQuizTypePicker(BuildContext context, String poemId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '选择测试模式',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('填空测试'),
                  subtitle: const Text('补全诗句中缺失的文字'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(
                      '${AppRoutes.poemQuizOf(poemId)}?type=fill',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('选择题'),
                  subtitle: const Text('根据上句选择正确的下句'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(
                      '${AppRoutes.poemQuizOf(poemId)}?type=choice',
                    );
                  },
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }
}
