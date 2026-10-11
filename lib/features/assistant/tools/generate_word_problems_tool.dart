// lib/features/assistant/tools/generate_word_problems_tool.dart
//
// 层级：features/assistant/tools
// 职责：出题工具。复用应用题出题管线（本地骨架 + LLM 题面 + 本地校验链），
//       经家长确认预览页入库——绝不静默入库。
//
// 安全边界：数学内容来自本地骨架生成器，LLM 只产出不可信题面；
//       草稿必经 WordProblemValidator 校验，入库由家长在预览页确认。
//       出题使用「AI 出题」场景配置（LlmScenario.wordProblem），非助手配置。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/tools/assistant_tool.dart';
import 'package:poemath/features/math/word_problem/word_problem_preview_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/features/math/word_problem/word_problem_validator.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// 出题工具：生成一组应用题草稿并打开家长预览页确认入库。
class GenerateWordProblemsTool extends AssistantTool {
  @override
  String get name => 'generate_word_problems';

  @override
  String get description =>
      '为孩子生成一组小学应用题并打开家长预览页确认后入库。'
      '题目的数字与答案在本地生成并校验，模型只负责题面文字。'
      '适用于孩子想练习某个知识点的应用题时。';

  @override
  Map<String, Object?> get parametersSchema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'grade': <String, Object?>{
            'type': 'integer',
            'description': '年级（1-6）',
          },
          'semester': <String, Object?>{
            'type': 'string',
            'description': '学期：上 或 下',
            'enum': <String>['上', '下'],
          },
          'topic': <String, Object?>{
            'type': 'string',
            'description':
                '知识点：addition/subtraction/multiplication/division/mixed',
            'enum': <String>[
              'addition',
              'subtraction',
              'multiplication',
              'division',
              'mixed',
            ],
          },
          'count': <String, Object?>{
            'type': 'integer',
            'description': '题目数量（1-10）',
          },
        },
        'required': <String>['grade', 'semester', 'topic', 'count'],
      };

  @override
  Future<ToolResult> execute(Ref ref, Map<String, dynamic> args) async {
    final grade = _asInt(args['grade']);
    final semester = args['semester']?.toString() ?? '';
    final topic = WordProblemTopic.tryParse(args['topic']?.toString() ?? '');
    final count = _asInt(args['count']);

    if (grade == null || grade < 1 || grade > 6) {
      return const ToolResult.error('年级无效，请提供 1-6 之间的年级。');
    }
    if (semester != '上' && semester != '下') {
      return const ToolResult.error('学期无效，请提供「上」或「下」。');
    }
    if (topic == null) {
      return const ToolResult.error(
        '知识点无效，可选 addition/subtraction/multiplication/division/mixed。',
      );
    }
    if (count == null || count < 1 || count > 10) {
      return const ToolResult.error('数量无效，请提供 1-10 之间的题数。');
    }

    // 出题走「AI 出题」场景配置，非助手配置。
    final config = await ref
        .read(settingsRepositoryProvider)
        .readLlmConfigForScenario(LlmScenario.wordProblem);
    if (config == null) {
      return const ToolResult.error('还没有配置 AI 出题服务，无法生成题目。');
    }

    final client = LlmClient(httpClient: ref.read(llmExplainHttpClientProvider));
    try {
      final skeletons = ref.read(wordProblemSkeletonProvider)(
        grade: grade,
        semester: semester,
        topic: topic.name,
        count: count,
      );
      final result = await client.generateWordProblems(
        config: config,
        skeletons: skeletons,
        grade: grade,
        semester: semester,
        topic: topic.label,
      );

      // 按 index（1-based）对齐骨架，逐题本地校验（复用出题页同管线）。
      final items = <WordProblemPreviewItem>[];
      for (var i = 0; i < skeletons.length; i++) {
        final skeleton = skeletons[i];
        final draft = _draftForIndex(result.drafts, i + 1);
        if (draft == null) {
          items.add(
            WordProblemPreviewItem(
              skeleton: skeleton,
              draft: null,
              rejectReason: 'LLM 未返回该题',
            ),
          );
          continue;
        }
        items.add(
          WordProblemPreviewItem(
            skeleton: skeleton,
            draft: draft,
            rejectReason:
                WordProblemValidator.validate(draft: draft, skeleton: skeleton),
          ),
        );
      }

      // 走家长确认预览页（context-free 导航），确认后才入库——绝不静默存。
      ref.read(appRouterProvider).push(
            AppRoutes.wordProblemPreview,
            extra: WordProblemPreviewData(
              grade: grade,
              semester: semester,
              topicName: topic.name,
              items: items,
            ),
          );

      final accepted = items.where((it) => it.accepted).length;
      return ToolResult(
        '已生成 ${items.length} 道${topic.label}题（其中 $accepted 道通过校验），'
        '并打开了家长预览页，确认后才会入库。',
      );
    } on LlmException catch (e) {
      return ToolResult.error('生成题目失败：${e.message}');
    } on ArgumentError catch (e) {
      return ToolResult.error('生成题目失败：${e.message}');
    } on StateError {
      return const ToolResult.error('题目结构生成失败，请更换年级或知识点后再试。');
    } finally {
      client.close();
    }
  }

  /// 从草稿列表取指定 1-based index 的草稿；无则 null。
  static LlmWordProblemDraft? _draftForIndex(
    List<LlmWordProblemDraft> drafts,
    int index,
  ) {
    for (final d in drafts) {
      if (d.index == index) return d;
    }
    return null;
  }

  /// 宽松解析整数（模型可能回 int/double/数字字符串）。
  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
