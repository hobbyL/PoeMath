// lib/features/math/word_problem/word_problem_generate_page.dart
//
// 层级：features/math/word_problem
// 职责：应用题 AI 出题生成页 —— 选择年级/学期/知识点/数量，
//       本地计划 + AI 素材选择 → 本地题面/讲解 → 家长预览确认入库。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/features/math/word_problem/word_problem_preview_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class WordProblemGeneratePage extends ConsumerStatefulWidget {
  const WordProblemGeneratePage({super.key});

  @override
  ConsumerState<WordProblemGeneratePage> createState() =>
      _WordProblemGeneratePageState();
}

class _WordProblemGeneratePageState
    extends ConsumerState<WordProblemGeneratePage> {
  int _grade = 2;
  String _semester = '上';
  WordProblemTopic _topic = WordProblemTopic.addition;

  /// 生成数量：PRD 约定默认 10，范围 5–20。
  int _count = 10;

  bool _generating = false;
  String? _errorMessage;

  DifficultyLevel get _difficulty => DifficultyLevel.values.byName(
        ref.read(settingsRepositoryProvider).mathDifficulty,
      );

  /// 年级/学期变更后，若当前知识点在新学期不教授，回退到首个可用项。
  /// 加法/减法在全部预设中恒存在，可用列表不会为空。调用方须自行置于 setState 内。
  void _ensureTopicAvailable() {
    final topics = WordProblemSkeletonGenerator.availableTopics(
      grade: _grade,
      semester: _semester,
      difficulty: _difficulty,
    );
    if (!topics.contains(_topic)) {
      _topic = topics.first;
    }
  }

  Future<void> _generate() async {
    if (_generating) return;

    _ensureTopicAvailable();

    setState(() {
      _generating = true;
      _errorMessage = null;
    });
    final grade = _grade;
    final semester = _semester;
    final topic = _topic;
    final count = _count;
    final difficulty = _difficulty;
    final settings = ref.read(settingsRepositoryProvider);
    final createService = ref.read(wordProblemGenerationServiceProvider);
    final client = createRuntimeLlmClient(
      httpClient: ref.read(llmExplainHttpClientProvider),
      settings: settings,
      isActive: () => mounted,
      onSelectionChanged: () =>
          ref.read(llmSelectionVersionProvider.notifier).state++,
    );
    try {
      final config = await settings.readLlmConfig();
      if (!mounted) return;
      if (config == null) {
        setState(() => _errorMessage = 'LLM 服务未配置');
        return;
      }
      // 经 provider 调用（测试可注入失败场景，如骨架重试耗尽的 StateError）。
      final generated = await createService(client).generate(
        config: config,
        grade: grade,
        semester: semester,
        topic: topic,
        count: count,
        difficulty: difficulty,
        isActive: () => mounted,
      );
      final items = [
        for (var i = 0; i < generated.length; i++)
          WordProblemPreviewItem.fromGenerated(generated[i], index: i + 1),
      ];

      if (!mounted) return;
      context.push(
        AppRoutes.wordProblemPreview,
        extra: WordProblemPreviewData(
          grade: grade,
          semester: semester,
          topicName: topic.name,
          items: items,
        ),
      );
    } on LlmException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } on ArgumentError catch (e) {
      // 学期未学习所选知识点等参数错误，直接展示中文原因。
      if (mounted) setState(() => _errorMessage = '${e.message}');
    } on StateError {
      // 骨架生成重试耗尽等结构生成失败，转中文提示（避免英文堆栈吓到家长）。
      if (mounted) {
        setState(() => _errorMessage = '题目结构生成失败，请重试或更换年级/知识点');
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '服务地址无效：${e.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '生成失败：$e');
    } finally {
      client.close();
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configAsync = ref.watch(llmConfigProvider);
    ref.watch(settingsRepositoryProvider);
    _ensureTopicAvailable();

    return Scaffold(
      appBar: AppBar(title: const Text('应用题 AI 出题')),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('配置读取失败')),
        data: (config) => ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            if (config == null) ...[
              // 未配置引导态
              ColoredCard(
                color: theme.colorScheme.tertiary,
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          '尚未配置 AI 出题服务',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      'AI 为应用题选择生活情境，题目与讲解在本地生成。需家长先配置一个 '
                      'OpenAI 兼容的大模型服务（地址、模型与 API Key），'
                      '生成后请核对题意、算式和讲解，再确认入库。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push(AppRoutes.llmSettings),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('去配置'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // 生成表单
              _buildGradeSelector(theme),
              const SizedBox(height: SpacingTokens.md),
              _buildSemesterSelector(theme),
              const SizedBox(height: SpacingTokens.md),
              Text(
                '出题难度：${_difficulty.label}（跟随练习设置）',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: SpacingTokens.md),
              _buildTopicSelector(theme),
              const SizedBox(height: SpacingTokens.md),
              _buildCountSelector(theme),
              const SizedBox(height: SpacingTokens.lg),

              if (_errorMessage != null) ...[
                ColoredCard(
                  color: theme.colorScheme.error,
                  width: double.infinity,
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],

              FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(_generating ? '生成中…' : '生成 $_count 题'),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                '生成后进入家长预览，确认通过的题目才会入库。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGradeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('年级', style: theme.textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.xs),
        // 一行展示，宽度不够时横向滚动（参考错题本页年级行）。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var grade = 1; grade <= 6; grade++) ...[
                if (grade > 1) const SizedBox(width: SpacingTokens.xs),
                ChoiceChip(
                  label: Text('$grade 年级'),
                  selected: _grade == grade,
                  onSelected: (_) => setState(() {
                    _grade = grade;
                    _ensureTopicAvailable();
                  }),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSemesterSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('学期', style: theme.textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.xs),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '上', label: Text('上学期')),
            ButtonSegment(value: '下', label: Text('下学期')),
          ],
          selected: {_semester},
          onSelectionChanged: (selection) => setState(() {
            _semester = selection.first;
            _ensureTopicAvailable();
          }),
        ),
      ],
    );
  }

  Widget _buildTopicSelector(ThemeData theme) {
    // 只渲染当前「年级+学期」实际教授的知识点，不学的直接隐藏，
    // 避免用户选中一个随后无法生成的知识点（如一年级的除法）。
    final topics = WordProblemSkeletonGenerator.availableTopics(
      grade: _grade,
      semester: _semester,
      difficulty: _difficulty,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('知识点', style: theme.textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.xs),
        // 一行展示，宽度不够时横向滚动（参考错题本页年级行）。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < topics.length; i++) ...[
                if (i > 0) const SizedBox(width: SpacingTokens.xs),
                ChoiceChip(
                  label: Text(topics[i].label),
                  selected: _topic == topics[i],
                  onSelected: (_) => setState(() => _topic = topics[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('数量（$_count 题）', style: theme.textTheme.titleSmall),
        Slider(
          value: _count.toDouble(),
          min: 5,
          max: 20,
          divisions: 15,
          label: '$_count',
          onChanged: (value) => setState(() => _count = value.round()),
        ),
      ],
    );
  }
}
