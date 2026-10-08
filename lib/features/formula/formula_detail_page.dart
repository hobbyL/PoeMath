// lib/features/formula/formula_detail_page.dart
//
// 公式详情页：公式展示、参数说明、记忆技巧、例题、收藏，
// 区域点击朗读（任务 10-07-formula-tts，交互镜像诗词详情页）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/formula/formula_speak_text.dart';
import 'package:poemath/features/formula/providers/formula_providers.dart';

/// 可播放区域目标：区域编号 + 播放文本（与诗词详情页同一模式）。
typedef _PlayTarget = ({int section, String playText});

class FormulaDetailPage extends ConsumerStatefulWidget {
  const FormulaDetailPage({super.key, required this.formulaId});

  final String formulaId;

  @override
  ConsumerState<FormulaDetailPage> createState() => _FormulaDetailPageState();
}

class _FormulaDetailPageState extends ConsumerState<FormulaDetailPage> {
  late final TtsService _tts;
  bool _isSpeaking = false;

  /// 点击可播区域后 → 首段音频就绪前的遮罩期，拦截一切重复点击。
  bool _isPreparing = false;

  /// 遮罩期语义：true = 停止中（遮罩文案「正在停止…」），
  /// false = 合成中（遮罩文案「语音合成中…」）。
  bool _isStopping = false;

  /// 当前播放区域：-1 无 / 0 公式 / 1 记忆技巧 / 2 例题。
  int _activeSection = -1;

  /// 当前持有页面播放态的会话 id，-1 表示无（空闲 / 已停止）。
  ///
  /// 身份来源是 [TtsService.currentSessionId]（服务唯一权威），页面只记录
  /// 「当前屏幕归谁」，不维护第二个计数器（tts-pending-cleanup R3 契约）。
  int _activeSessionId = -1;

  /// 该回调 / 该次 await 是否仍属于当前持有页面播放态的会话。
  bool _isCurrentSession(int sessionId) => sessionId == _activeSessionId;

  /// 区域编号常量：0 公式区 / 1 记忆技巧 / 2 例题。
  static const int _sectionFormula = 0;
  static const int _sectionMemoryTip = 1;
  static const int _sectionExample = 2;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
  }

  @override
  void dispose() {
    // 页面销毁时停止朗读（返回退出等销毁场景）。注意：关联公式导航走
    // Navigator.push，旧页仅压栈不销毁——导航前停止由
    // [_onTapRelatedFormula] 负责（10-08 修复）。
    unawaited(
      _tts.stop().onError(
            (error, stackTrace) => AppLogger.e(
              '退出公式详情页时停止朗读失败',
              tag: 'FormulaDetail',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
    super.dispose();
  }

  /// 区域点击统一入口，语义与诗词详情页一致：
  /// - 遮罩期点击：直接忽略（遮罩本身也拦截，此处双保险）
  /// - 点击正在朗读的区域：先置停止遮罩再 stop
  /// - 朗读中点击其他区域：先停止当前并播放新区域；stop 失败则提示并
  ///   放弃切换，避免新旧会话在同一引擎上双读
  /// - 空闲点击：播放该区域
  Future<void> _onTapSection(_PlayTarget target) async {
    if (_isPreparing) return;
    if (_isSpeaking && _activeSection == target.section) {
      setState(() {
        _isPreparing = true;
        _isStopping = true;
      });
      await _stopSpeaking();
      if (mounted) {
        setState(() {
          _isPreparing = false;
          _isStopping = false;
        });
      }
      return;
    }
    if (_isSpeaking) {
      // 先置遮罩再 await stop：挡住停止窗口期的连点。
      setState(() {
        _isPreparing = true;
        _isStopping = true;
      });
      final stopped = await _stopSpeaking();
      if (!stopped) {
        if (mounted) {
          setState(() {
            _isPreparing = false;
            _isStopping = false;
          });
        }
        return;
      }
    }
    if (!mounted) return;
    await _startSpeak(target.section, target.playText);
  }

  /// 关联公式导航入口，镜像 [_onTapSection] 的停止语义（10-08 F1 修复）：
  /// push 不销毁旧页——若带着在播音频导航，新页空闲态无停止入口，
  /// 旧朗读会在新页下继续播放。故与跨区切换同语义：朗读中先停止，
  /// **stop 成功才导航**；失败则提示（SnackBar 由 [_stopSpeaking] 弹）并
  /// 留在本页，播放态保留。
  Future<void> _onTapRelatedFormula(String id) async {
    if (_isPreparing) return;
    if (_isSpeaking) {
      // 先置遮罩再 await stop：挡住停止窗口期的连点。
      setState(() {
        _isPreparing = true;
        _isStopping = true;
      });
      final stopped = await _stopSpeaking();
      if (mounted) {
        setState(() {
          _isPreparing = false;
          _isStopping = false;
        });
      }
      if (!stopped) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      fadeSlideRoute<void>(
        builder: (_) => FormulaDetailPage(formulaId: id),
      ),
    );
  }

  /// 停止当前朗读并清理播放态。
  ///
  /// 返回 stop 是否成功；失败时已弹 SnackBar，调用方不得启动新朗读。
  /// stop 失败保留播放态：音频可能仍在播，页面不得显示空闲。
  Future<bool> _stopSpeaking() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '停止公式朗读失败',
        tag: 'FormulaDetail',
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
    // 仅成功路径清态；交还播放态归属后旧会话晚到回调不再匹配。
    _activeSessionId = -1;
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _activeSection = -1;
      });
    }
    return true;
  }

  /// 播放指定区域文本（分句朗读 + onReady 解除遮罩）。
  Future<void> _startSpeak(int section, String text) async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      _isPreparing = true;
      _isStopping = false;
      _isSpeaking = true;
      _activeSection = section;
    });
    // `Future.sync` 归一发起时的同步抛错，使「捕获会话 id」一定先于
    // 异常被观察到（诗词详情页同一模式，见 state-management.md）。
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
    // 入口同步段之后立即读取：发起与读取之间无挂起点，读到的即本次
    // 会话 id（TtsService R3 契约）。
    final sessionId = _tts.currentSessionId;
    _activeSessionId = sessionId;
    try {
      await speaking;
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '公式朗读失败',
        tag: 'FormulaDetail',
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
      // 兜底清理：异常路径下 onReady 可能未触发，遮罩不允许卡死；
      // 过期会话不清理，避免复位新会话的播放态。
      if (_isCurrentSession(sessionId)) {
        _activeSessionId = -1;
        if (mounted) {
          setState(() {
            _isPreparing = false;
            _isSpeaking = false;
            _activeSection = -1;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formula = ref.watch(formulaByIdProvider(widget.formulaId));
    final isFav = ref.watch(isFormulaFavoriteProvider(widget.formulaId));
    final theme = Theme.of(context);

    if (formula == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('公式详情')),
        body: const Center(child: Text('公式未找到')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(formula.name),
        actions: [
          AnimatedFavoriteButton(
            isFavorite: isFav,
            activeIcon: Icons.bookmark,
            inactiveIcon: Icons.bookmark_border,
            onToggle: () async {
              final repo = ref.read(formulaFavoriteRepoProvider);
              await repo.toggle(widget.formulaId);
              ref.invalidate(isFormulaFavoriteProvider(widget.formulaId));
            },
          ),
        ],
      ),
      // 遮罩只覆盖内容区（不遮 AppBar 返回与收藏）。
      body: Stack(
        children: [
          AnimatedPageBody(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            children: [
              // 分类 + 年级标签
              Row(
                children: [
                  _buildTag(
                    context,
                    formula.category,
                    theme.colorScheme.primary,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  _buildTag(
                    context,
                    '${formula.grade}年级',
                    theme.colorScheme.secondary,
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.lg),

              // 公式展示（LaTeX 渲染，解析失败时降级为纯文本）。
              // 点击朗读「公式名 + 参数释义」（符号串不朗读，既定决策）。
              // 播放指示（10-08 F2 修复）：公式区无标题行，指示以角落
              // 叠加方式渲染——Stack 不改变 LaTeX 居中排版，指示出现/
              // 消失也不扰动卡片高度（ListView 内避免布局跳动）。
              _buildSection(
                context,
                section: _sectionFormula,
                playText: formulaSpeakText(formula),
                child: Stack(
                  children: [
                    Center(
                      child: formula.formulaLatex.isNotEmpty
                          ? Math.tex(
                              formula.formulaLatex,
                              textStyle:
                                  theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                              onErrorFallback: (_) => Text(
                                formula.formulaText,
                                style:
                                    theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                  letterSpacing: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : Text(
                              formula.formulaText,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                letterSpacing: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                    ),
                    if (_isSectionPlaying(_sectionFormula))
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Icon(
                          Icons.graphic_eq,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),

              // 参数说明
              if (formula.params.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildLabeledSection(
                  context,
                  '参数说明',
                  Icons.info_outline,
                  child: Column(
                    children: formula.params.map((param) {
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: SpacingTokens.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${param.symbol}：',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                param.meaning,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              // 记忆技巧（朗读原文过符号读音替换）
              if (formula.memoryTip.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildLabeledSection(
                  context,
                  '记忆技巧',
                  Icons.lightbulb_outline,
                  section: _sectionMemoryTip,
                  playText: replaceFormulaSymbols(formula.memoryTip),
                  child: Text(
                    formula.memoryTip,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              ],

              // 例题（朗读原文过符号读音替换）
              if (formula.example.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildLabeledSection(
                  context,
                  '例题',
                  Icons.quiz_outlined,
                  section: _sectionExample,
                  playText: replaceFormulaSymbols(formula.example),
                  child: Text(
                    formula.example,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              ],

              // 关联公式
              if (formula.relatedFormulas.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildLabeledSection(
                  context,
                  '关联公式',
                  Icons.link,
                  child: Wrap(
                    spacing: SpacingTokens.sm,
                    children: formula.relatedFormulas.map((id) {
                      final related = ref.watch(formulaByIdProvider(id));
                      return ActionChip(
                        label: Text(related?.name ?? id),
                        onPressed: related != null
                            ? () => _onTapRelatedFormula(id)
                            : null,
                      );
                    }).toList(),
                  ),
                ),
              ],

              const SizedBox(height: SpacingTokens.xl),
            ],
          ),

          // 合成中遮罩：模态层而非信息卡片，豁免 ColoredCard 规范
          // （与诗词详情页同一豁免）。半透明 Container 在命中测试中拦截
          // 点击，天然阻止遮罩期重复触发。
          if (_isPreparing)
            Positioned.fill(
              child: Container(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: SpacingTokens.md),
                    Text(
                      _isStopping ? '正在停止…' : '语音合成中…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTag(BuildContext context, String text, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: SpacingTokens.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 该区域当前是否处于播放中（三区域指示共用判定）。
  bool _isSectionPlaying(int section) =>
      _isSpeaking && _activeSection == section;

  /// 可播放区域卡片：[section] 非空时点击朗读，播放中标题旁显示
  /// `graphic_eq` 指示图标；[playText] 为朗读文本（section 非空时必传）。
  Widget _buildSection(
    BuildContext context, {
    int? section,
    String? playText,
    required Widget child,
  }) {
    assert(section == null || playText != null, '可播区域必须提供朗读文本');
    return ColoredCard(
      color: Theme.of(context).colorScheme.primary,
      backgroundOpacity: 0.06,
      padding: const EdgeInsets.all(SpacingTokens.lg),
      width: double.infinity,
      onTap: section == null
          ? null
          : () => _onTapSection((section: section, playText: playText!)),
      child: child,
    );
  }

  /// 带标题的区域卡片（记忆技巧 / 例题 / 参数说明等）。
  ///
  /// [section] + [playText] 提供时整卡可点击朗读，播放中标题旁显示指示
  /// 图标；不传则为纯展示区（参数说明 / 关联公式）。
  Widget _buildLabeledSection(
    BuildContext context,
    String label,
    IconData icon, {
    int? section,
    String? playText,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final playing = section != null && _isSectionPlaying(section);
    return _buildSection(
      context,
      section: section,
      playText: playText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (playing) ...[
                const SizedBox(width: SpacingTokens.xs),
                Icon(
                  Icons.graphic_eq,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          child,
        ],
      ),
    );
  }
}
