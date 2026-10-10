// lib/features/math/widgets/math_ai_explain_sheet.dart
//
// 层级：features/math/widgets
// 职责：算数题 AI 解析底部弹层 —— 练习页讲解区与错题详情页共用入口。
//
// 四态（未生成 / 生成中 / 已就绪 / 失败 / 未配置）与诗词侧同构；
// 生成中用纯文案提示（不放无限动画）；关闭弹层即复位状态。
//
// 边界：只展示讲解，不参与判分与错题记录。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/math/math_explain/math_explain_controller.dart';
import 'package:poemath/features/math/math_explain/math_explain_models.dart';

/// 打开 AI 解析弹层并立即发起生成；关闭后复位状态。
Future<void> showMathAiExplainSheet(
  BuildContext context, {
  required String problemText,
  required String correctAnswer,
  String? userAnswer,
  String? diagnosisCategory,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => MathAiExplainSheet(
      problemText: problemText,
      correctAnswer: correctAnswer,
      userAnswer: userAnswer,
      diagnosisCategory: diagnosisCategory,
    ),
  );
}

/// AI 解析弹层内容。
class MathAiExplainSheet extends ConsumerStatefulWidget {
  const MathAiExplainSheet({
    super.key,
    required this.problemText,
    required this.correctAnswer,
    this.userAnswer,
    this.diagnosisCategory,
  });

  final String problemText;
  final String correctAnswer;
  final String? userAnswer;
  final String? diagnosisCategory;

  @override
  ConsumerState<MathAiExplainSheet> createState() =>
      _MathAiExplainSheetState();
}

class _MathAiExplainSheetState extends ConsumerState<MathAiExplainSheet> {
  /// dispose 阶段 ref 不可用，initState 先捕获 notifier。
  late final MathExplainNotifier _notifier;

  /// TTS 服务（dispose 阶段 ref 不可用，initState 先捕获）。
  late final TtsService _tts;

  /// 是否正在朗读解析内容。
  bool _isSpeaking = false;

  /// 点击可播区域 → 首段音频就绪前（或停止 await 期）的遮罩期，
  /// 作为重入守卫拦截一切重复点击，避免 stop 未完成时并发启动第二个会话。
  bool _isPreparing = false;

  /// 当前持有播放态的会话 id，-1 表示无（空闲 / 已停止）。
  /// 身份来源是 [TtsService.currentSessionId]（服务唯一权威）。
  int _activeSessionId = -1;

  /// 该回调 / 该次 await 是否仍属于当前持有播放态的会话。
  bool _isCurrentSession(int sessionId) => sessionId == _activeSessionId;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(mathExplainProvider.notifier);
    _tts = ref.read(ttsServiceProvider);
    // 打开即生成（入口按钮本身就是用户的生成意图）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 上一个弹层关闭时在途请求被 discardPending 废弃，state 可能残留
      // loading——先复位（idle + 废令牌）再生成，否则 generate 的
      // isLoading 守卫拦截且无任何自愈路径（loading 分支无按钮）。
      _notifier.reset();
      _generate();
    });
  }

  @override
  void dispose() {
    // 关闭弹层：仅令牌失效（丢弃在途请求晚到回调）。不在此写
    // provider 状态——弹层元素在 unmount 期间仍订阅该 provider，
    // 同步状态写会通知 defunct element 触发 markNeedsBuild 断言。
    _notifier.discardPending();
    // 关闭弹层即停播（AC12「关闭停播」）：stop 同步段递增服务令牌，
    // 在途朗读的晚到回调天然失配。
    unawaited(
      _tts.stop().onError(
            (error, stackTrace) => AppLogger.e(
              '关闭 AI 解析弹层时停止朗读失败',
              tag: 'MathAiExplain',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
    super.dispose();
  }

  void _generate() {
    _notifier.generate(
      problemText: widget.problemText,
      correctAnswer: widget.correctAnswer,
      userAnswer: widget.userAnswer,
      diagnosisCategory: widget.diagnosisCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(mathExplainProvider);
    final playing = _isSpeaking;

    // 标题右侧状态操作 tag：生成中/重新生成/去设置收敛到此，正文不再放按钮。
    // 弹层打开即自动生成，idle 仅为瞬时态，与 loading 同样显示「生成中…」。
    final actionTag = switch (state.status) {
      MathExplainStatus.idle ||
      MathExplainStatus.loading =>
        const AiActionTag(label: '生成中…', busy: true),
      MathExplainStatus.ready => AiActionTag(
          label: '重新生成',
          onTap: _generate,
        ),
      MathExplainStatus.error => AiActionTag(
          label: '重新生成',
          onTap: _generate,
        ),
      MathExplainStatus.unconfigured => AiActionTag(
          label: '去设置',
          onTap: () {
            Navigator.of(context).pop();
            context.push(AppRoutes.llmSettings);
          },
        ),
    };

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Text(
                    'AI 解析',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (playing) ...[
                    const SizedBox(width: SpacingTokens.xs),
                    Icon(
                      Icons.graphic_eq,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                  ],
                  const SizedBox(width: SpacingTokens.sm),
                  actionTag,
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: ColoredCard(
                    color: theme.colorScheme.tertiary,
                    backgroundOpacity: 0.06,
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildBody(theme, state),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    ThemeData theme,
    MathExplainState state,
  ) {
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    switch (state.status) {
      case MathExplainStatus.idle:
      case MathExplainStatus.loading:
        return [
          Text('AI 正在准备解析，请稍候…', style: hintStyle),
        ];
      case MathExplainStatus.ready:
        return [
          // 内容区可点击播放：点击朗读，再次点击停止（竞态由会话令牌护栏）。
          InkWell(
            onTap: () => _onTapContent(state.fullText),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final paragraph in state.paragraphs) ...[
                  Text(
                    paragraph,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                ],
              ],
            ),
          ),
          Text('点击内容可朗读，再次点击停止。', style: hintStyle),
        ];
      case MathExplainStatus.error:
        return [
          Text(
            state.message ?? 'AI 解析生成失败，请稍后重试。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ];
      case MathExplainStatus.unconfigured:
        return [
          Text(
            state.message ?? '还没有配置 AI 服务，配置后即可使用 AI 解析。',
            style: hintStyle,
          ),
        ];
    }
  }

  /// 内容区点击：空闲→朗读，朗读中→停止（单区域，无切换分支）。
  Future<void> _onTapContent(String text) async {
    if (_isPreparing) return;
    if (_isSpeaking) {
      // 先置遮罩再 await stop：挡住停止窗口期的二次点击，避免 stop
      // 未完成时并发启动第二个会话。
      setState(() => _isPreparing = true);
      await _stopSpeaking();
      if (mounted) setState(() => _isPreparing = false);
      return;
    }
    if (!mounted) return;
    await _startSpeak(text);
  }

  /// 停止当前朗读并清理播放态。返回 stop 是否成功；失败时已弹 SnackBar。
  /// 失败保留 `_isSpeaking`（音频可能仍在播），让后续点击继续走停止路由。
  Future<bool> _stopSpeaking() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '停止 AI 解析朗读失败',
        tag: 'MathAiExplain',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('停止朗读失败，请稍后重试')),
        );
      }
      return false;
    }
    _activeSessionId = -1;
    if (mounted) setState(() => _isSpeaking = false);
    return true;
  }

  /// 朗读解析内容（按标点分句）。会话令牌护栏复用诗词侧纪律：
  /// `Future.sync` 使「捕获会话 id」一定先于任何异常/回调被观察到。
  Future<void> _startSpeak(String text) async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      _isPreparing = true;
      _isSpeaking = true;
    });
    final speaking = Future.sync(() {
      return _tts.speakSentences(
        text,
        onReady: (sessionId) {
          if (mounted && _isCurrentSession(sessionId)) {
            setState(() => _isPreparing = false);
          }
        },
      );
    });
    // 朗读入口在任何 await 之前递增服务令牌，发起与读取之间无挂起点。
    final sessionId = _tts.currentSessionId;
    _activeSessionId = sessionId;
    try {
      await speaking;
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        'AI 解析朗读失败',
        tag: 'MathAiExplain',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && _isCurrentSession(sessionId)) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          SnackBar(
            content: Text(
              error is TtsException
                  ? '朗读失败：${error.message}'
                  : '朗读失败，请检查系统语音服务后重试',
            ),
          ),
        );
      }
    } finally {
      // 过期会话（已被 stop/新会话接管）不清理，避免复位新会话的状态。
      if (_isCurrentSession(sessionId)) {
        _activeSessionId = -1;
        if (mounted) {
          setState(() {
            _isPreparing = false;
            _isSpeaking = false;
          });
        }
      }
    }
  }
}
