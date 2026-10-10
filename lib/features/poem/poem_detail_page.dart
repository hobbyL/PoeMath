// lib/features/poem/poem_detail_page.dart
//
// 诗词详情页：展示全文、拼音、译文、赏析、注释，可收藏、TTS朗读和开始背诵。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_author_bios.dart';
import 'package:poemath/features/poem/poem_explain/poem_explain_controller.dart';
import 'package:poemath/features/poem/poem_explain/poem_explain_models.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

/// 拼音显隐状态 Provider（读取 SettingsRepository 的持久化值）。
final _pinyinVisibleProvider = StateProvider<bool>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return settings.pinyinVisible;
});

/// 可播放区域目标：区域编号 + 播放文本。
///
/// 以单一 record 参数在折叠区构建与点击入口之间传递（R5），
/// 编译期保证两者同进同出——只传其一会失去可播性的旧双参数
/// 形态不再存在。
typedef _PlayTarget = ({int section, String playText});

class PoemDetailPage extends ConsumerStatefulWidget {
  const PoemDetailPage({super.key, required this.poemId});

  final String poemId;

  @override
  ConsumerState<PoemDetailPage> createState() => _PoemDetailPageState();
}

class _PoemDetailPageState extends ConsumerState<PoemDetailPage> {
  late final TtsService _tts;
  bool _isSpeaking = false;

  /// 点击可播区域后 → 首段音频就绪前的遮罩期，拦截一切重复点击。
  bool _isPreparing = false;

  /// 遮罩期语义：true = 停止中（遮罩文案「正在停止…」），
  /// false = 合成中（遮罩文案「语音合成中…」）。
  ///
  /// 同区停止与切换停止先置遮罩再 await stop，挂起窗口期实际处于
  /// 「停止中」而非「合成中」，文案需要区分（缺陷 7）。
  bool _isStopping = false;

  /// 当前播放区域：-1 无 / 0 正文 / 1..5 折叠区（见 _Section 常量）。
  int _activeSection = -1;

  /// 当前正在朗读的行索引，-1 表示未朗读。
  int _currentLineIndex = -1;

  /// 当前持有页面播放态的会话 id，-1 表示无（空闲 / 已停止）。
  ///
  /// 场景：切换区域时「先 stop 再播」——旧朗读的 Future 可能在新区域
  /// 已开始播放后才被引擎唤醒，其 finally/onLineStart 会把新区域的
  /// 播放态错误复位。
  ///
  /// 身份来源是 [TtsService.currentSessionId]（服务唯一权威），页面不再
  /// 自建代际计数器与服务 lockstep 维护——旧的页面自增代际方案在任何
  /// 绕过 `_stopSpeaking` 的 stop（如 dispose）处会与服务漂移
  /// （挂账 R3）。本字段只是「当前屏幕归谁」的记录，不是第二个计数器。
  int _activeSessionId = -1;

  /// 该回调 / 该次 await 是否仍属于当前持有页面播放态的会话。
  bool _isCurrentSession(int sessionId) => sessionId == _activeSessionId;

  /// 区域编号常量：正文为 0，折叠区 1..5。
  static const int _sectionContent = 0;
  static const int _sectionTranslation = 1;
  static const int _sectionAnnotations = 2;
  static const int _sectionAppreciation = 3;
  static const int _sectionBackground = 4;
  static const int _sectionFamousLines = 5;

  /// AI 讲解区（可朗读，复用同一套朗读会话纪律）。
  static const int _sectionAiExplain = 6;

  /// AI 讲解控制器：dispose 时仍可安全调用（只令牌失效，不写状态），
  /// ref 在 dispose 阶段不可用，故在 initState 捕获 notifier。
  late final PoemExplainNotifier _explainNotifier;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    _explainNotifier = ref.read(poemExplainProvider.notifier);
    // 进入页面时复位上一首遗留的讲解状态。postFrame：不在 build
    // 阶段写 provider 状态（同步通知其它已挂载的监听元素会触发
    // markNeedsBuild during build 断言）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _explainNotifier.reset();
    });
  }

  @override
  void dispose() {
    // 退出页面：仅令牌失效，丢弃在途请求的晚到回调。不在此写
    // provider 状态——退页元素在 unmount 期间仍订阅该 provider，
    // 同步状态写会通知 defunct element 触发断言。
    _explainNotifier.discardPending();
    // 退出页面时停止朗读
    unawaited(
      _tts.stop().onError(
            (error, stackTrace) => AppLogger.e(
              '退出诗词详情页时停止朗读失败',
              tag: 'PoemDetail',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
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

  /// 区域点击统一入口。
  ///
  /// 语义（PRD R2/R3）：
  /// - 遮罩期点击：直接忽略（遮罩本身也拦截，此处双保险）
  /// - 点击正在朗读的区域：仅停止——同样先置遮罩再 stop，挡住停止
  ///   挂起期的连点（缺陷 3：第二次点击被 `_isPreparing` 代码守卫拦截，
  ///   不会二次 stop）
  /// - 朗读中点击其他区域：先置遮罩再停止当前并播放新区域——遮罩挡住
  ///   停止窗口期的连点（R3）；stop 失败则提示并放弃切换，不启动新朗读，
  ///   避免新旧会话在同一引擎上双读（R2）
  /// - 空闲点击：播放该区域
  Future<void> _onTapSection(_PlayTarget target) async {
    if (_isPreparing) return;
    if (_isSpeaking && _activeSection == target.section) {
      // 同区停止同样进入遮罩：与切换分支一致的重入守卫（缺陷 3）。
      // 遮罩文案为停止语义（缺陷 7）。
      setState(() {
        _isPreparing = true;
        _isStopping = true;
      });
      await _stopSpeaking();
      // 成败均复位遮罩；stop 失败时 `_isSpeaking` 由 `_stopSpeaking`
      // 保留（音频可能仍在播），遮罩不允许挂死。
      if (mounted) {
        setState(() {
          _isPreparing = false;
          _isStopping = false;
        });
      }
      return;
    }
    if (_isSpeaking) {
      // 先置遮罩再 await stop：挡住停止窗口期的二次点击（R3），
      // 避免 stop 未完成时并发启动第二个朗读会话。遮罩文案为停止
      // 语义（缺陷 7）。
      setState(() {
        _isPreparing = true;
        _isStopping = true;
      });
      final stopped = await _stopSpeaking();
      if (!stopped) {
        // stop 失败：SnackBar 已在 _stopSpeaking 内弹出，放弃切换（R2）。
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

  /// 停止当前朗读并清理全部播放态。
  ///
  /// 返回 stop 是否成功；失败时已弹出 SnackBar 提示，调用方不得启动
  /// 新朗读（否则新旧会话双读）。
  ///
  /// 状态语义（缺陷 1）：stop 失败时引擎音频可能仍在播——**保留**
  /// `_isSpeaking` / `_activeSection` / `_currentLineIndex`（页面不得
  /// 显示空闲，否则再点任意区域会绕过停止直达新朗读），让后续点击
  /// 继续走停止路由；仅成功路径清态。
  Future<bool> _stopSpeaking() async {
    // 页面不再递增自有令牌：`_tts.stop()` 在其同步段即递增服务令牌，
    // 旧会话的后续回调天然失配（挂账 R3）。
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '停止诗词朗读失败',
        tag: 'PoemDetail',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('停止朗读失败，请稍后重试')),
        );
      }
      // 失败保留播放态：音频确实还在播，页面不得显示空闲（缺陷 1）。
      return false;
    }
    // 仅成功路径清态（原 finally 无条件清态是缺陷 1 的 UI 半边）。
    // 交还播放态归属：此后旧会话的任何晚到回调都不再匹配（R3）。
    _activeSessionId = -1;
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _currentLineIndex = -1;
        _activeSection = -1;
      });
    }
    return true;
  }

  /// 播放指定区域：正文（section 0）逐行朗读 + 当前行高亮；
  /// 折叠区按标点分句朗读，不做逐行高亮。
  Future<void> _startSpeak(int section, String text) async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      _isPreparing = true;
      _isStopping = false; // 新朗读遮罩回到合成语义。
      _isSpeaking = true;
      _activeSection = section;
    });
    // 回调内比对的是「发起时捕获的会话 id」，闭包在调用时才读
    // `_activeSessionId`，而回调最早只能在服务首个 await 之后触发
    // （朗读入口的同步段不触发任何回调）——因此下方捕获赋值一定先于
    // 任何回调执行。
    //
    // `Future.sync` 包裹：把发起时的同步抛错归一为 Future 失败，使
    // 「捕获会话 id」一定先于异常被观察到——否则同步抛错会越过捕获
    // 与下方 catch/finally，遮罩卡死且无失败提示。
    final speaking = Future.sync(() {
      if (section == _sectionContent) {
        final lines = _splitLines(text);
        return _tts.speakLines(
          lines,
          onLineStart: (index, sessionId) {
            if (mounted && _isCurrentSession(sessionId)) {
              setState(() => _currentLineIndex = index);
            }
          },
          onReady: (sessionId) {
            if (mounted && _isCurrentSession(sessionId)) {
              setState(() => _isPreparing = false);
            }
          },
        );
      }
      return _tts.speakSentences(
        text,
        onReady: (sessionId) {
          if (mounted && _isCurrentSession(sessionId)) {
            setState(() => _isPreparing = false);
          }
        },
      );
    });
    // 会话 id 在入口同步段之后立即读取：朗读入口在任何 await 之前递增
    // 服务令牌，发起与读取之间没有挂起点，读到的即本次会话 id（R3）。
    final sessionId = _tts.currentSessionId;
    _activeSessionId = sessionId;
    try {
      await speaking;
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '诗词朗读失败',
        tag: 'PoemDetail',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && _isCurrentSession(sessionId)) {
        // TtsException.message 已是面向用户的中文文案（如云端全跳句的
        // 「云端音频播放失败，请稍后重试」），直接透传；其他异常保留
        // 通用兜底——云端播放失败不再被误导为系统引擎问题（缺陷 2）。
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
      // 兜底清理：异常路径下 onReady 可能未触发，遮罩不允许卡死。
      // 过期会话（已被 stop/新会话接管）不清理，避免复位新会话的状态。
      if (_isCurrentSession(sessionId)) {
        _activeSessionId = -1;
        if (mounted) {
          setState(() {
            _isPreparing = false;
            _isSpeaking = false;
            _currentLineIndex = -1;
            _activeSection = -1;
          });
        }
      }
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

    // 注释播放文本：按「词：释义」逐条拼接。
    final annotationsText = poem.annotations
        .map((ann) => '${ann.word}：${ann.meaning}')
        .join('。');
    // 名句播放文本：按行拼接。
    final famousLinesText = poem.famousLines.join('。');

    return Scaffold(
      appBar: AppBar(
        title: Text(poem.title),
        actions: [
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
      // 遮罩只覆盖内容区（不遮挡底部操作栏与 AppBar 返回）。
      body: Stack(
        children: [
          AnimatedPageBody(
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

              // 正文（整块可点击朗读，逐行显示，朗读时当前行高亮）
              _buildSection(
                context,
                onTap: () => _onTapSection(
                  (section: _sectionContent, playText: poem.content),
                ),
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
                  playTarget: (
                    section: _sectionTranslation,
                    playText: poem.translation,
                  ),
                  child: Text(
                    poem.translation,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
                  ),
                ),
              ],

              // 注释
              if (poem.annotations.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildCollapsibleSection(
                  context,
                  icon: Icons.edit_note,
                  title: '注释',
                  playTarget: (
                    section: _sectionAnnotations,
                    playText: annotationsText,
                  ),
                  child: _buildAnnotationsList(context, poem),
                ),
              ],

              // 赏析
              if (poem.appreciation.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildCollapsibleSection(
                  context,
                  icon: Icons.local_florist_outlined,
                  title: '赏析',
                  playTarget: (
                    section: _sectionAppreciation,
                    playText: poem.appreciation,
                  ),
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
                  playTarget: (
                    section: _sectionBackground,
                    playText: poem.background,
                  ),
                  child: Text(
                    poem.background,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
                  ),
                ),
              ],

              // 名句
              if (poem.famousLines.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildCollapsibleFamousLines(
                  context,
                  poem.famousLines,
                  famousLinesText,
                ),
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

              // AI 讲解
              const SizedBox(height: SpacingTokens.md),
              _buildAiExplainSection(context, poem),

              // 学习状态
              if (progress != null) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildProgressInfo(context, progress.studyCount),
              ],
              const SizedBox(height: SpacingTokens.xl),
            ],
          ),

          // 合成中遮罩：模态层而非信息卡片，豁免 ColoredCard 规范。
          if (_isPreparing)
            Positioned.fill(
              // 半透明 Container 在命中测试中拦截点击，天然阻止遮罩期重复触发。
              child: Container(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: SpacingTokens.md),
                    // 遮罩文案区分语义：合成期「语音合成中…」、停止挂起期
                    // 「正在停止…」（缺陷 7：停止窗口期显示合成文案误导）。
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
        ) ??
        TypographyTokens.poemContentStyle();

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
          // 诗句行单行自适应：只缩不放，缩到正文字号下限仍放不下则换行。
          child: AutoFitText(
            text: lines[i],
            style: isActive
                ? baseStyle.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  )
                : baseStyle,
            minFontSize:
                theme.textTheme.bodyMedium?.fontSize ?? TypographyTokens.fsBody,
          ),
        );
      }),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required Widget child,
    VoidCallback? onTap,
  }) {
    return ColoredCard(
      color: Theme.of(context).colorScheme.primary,
      backgroundOpacity: 0.06,
      width: double.infinity,
      onTap: onTap,
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
  ///
  /// [playTarget] 提供时，展开后的内容区域可点击播放该目标文本，
  /// 播放中在标题旁显示 graphic_eq 小图标（不参与点击的作者简介等不传）。
  Widget _buildCollapsibleSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
    _PlayTarget? playTarget,
  }) {
    final theme = Theme.of(context);
    final playing = playTarget != null &&
        _isSpeaking &&
        _activeSection == playTarget.section;
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
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
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
          shape: const Border(),
          collapsedShape: const Border(),
          // 展开内容可点击播放：playTarget 非空时在此统一包裹，
          // 调用点只传单一目标参数（R5），指示图标与播放文本永不错位。
          children: [
            if (playTarget != null)
              _buildPlayableChild(playTarget, child)
            else
              child,
          ],
        ),
      ),
    );
  }

  /// 折叠区展开内容的播放包裹（[_buildCollapsibleSection] 内部实现细节）。
  ///
  /// 仅包内容 child，不包标题行——折叠态点击标题仍走展开/收起。
  Widget _buildPlayableChild(_PlayTarget target, Widget child) {
    return InkWell(
      onTap: () => _onTapSection(target),
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  /// 注释列表内容（视觉展示，与播放文本「词：释义」拼接分离）。
  Widget _buildAnnotationsList(BuildContext context, Poem poem) {
    final theme = Theme.of(context);
    return Column(
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
    );
  }

  /// 名句折叠区块。
  Widget _buildCollapsibleFamousLines(
    BuildContext context,
    List<String> lines,
    String playText,
  ) {
    final theme = Theme.of(context);
    return _buildCollapsibleSection(
      context,
      icon: Icons.format_quote,
      title: '名句',
      playTarget: (section: _sectionFamousLines, playText: playText),
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

  /// AI 讲解区：四态卡片（未生成 / 生成中 / 已就绪 / 失败 / 未配置）。
  ///
  /// 生成中不放无限动画（纯文案提示），请求结束由控制器切态复位。
  Widget _buildAiExplainSection(BuildContext context, Poem poem) {
    final theme = Theme.of(context);
    final raw = ref.watch(poemExplainProvider);
    // 只认当前诗词的结果：切诗后旧内容不得闪现。
    final state = (raw.poemId == null || raw.poemId == poem.id)
        ? raw
        : const PoemExplainState();
    final playing = _isSpeaking && _activeSection == _sectionAiExplain;

    // 标题右侧状态操作 tag：生成/重新生成/去设置均收敛到此，正文不再放按钮。
    final actionTag = switch (state.status) {
      PoemExplainStatus.idle => AiActionTag(
          label: '生成讲解',
          onTap: () => _explainNotifier.generate(poem),
        ),
      PoemExplainStatus.loading ||
      PoemExplainStatus.streaming =>
        const AiActionTag(
          label: '生成中…',
          busy: true,
        ),
      PoemExplainStatus.ready => AiActionTag(
          label: '重新生成',
          onTap: () => _explainNotifier.generate(poem),
        ),
      PoemExplainStatus.error => AiActionTag(
          label: '重新生成',
          onTap: () => _explainNotifier.generate(poem),
        ),
      PoemExplainStatus.unconfigured => AiActionTag(
          label: '去设置',
          onTap: () => context.push(AppRoutes.llmSettings),
        ),
    };

    return ColoredCard(
      color: theme.colorScheme.tertiary,
      backgroundOpacity: 0.06,
      width: double.infinity,
      child: Column(
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
                'AI 讲解',
                style: theme.textTheme.titleSmall?.copyWith(
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
              const Spacer(),
              actionTag,
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          ..._buildAiExplainBody(theme, state),
        ],
      ),
    );
  }

  List<Widget> _buildAiExplainBody(
    ThemeData theme,
    PoemExplainState state,
  ) {
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    switch (state.status) {
      case PoemExplainStatus.idle:
        return [
          Text(
            '点右上角「生成讲解」，让 AI 用小朋友能听懂的话讲讲这首诗。',
            style: hintStyle,
          ),
        ];
      case PoemExplainStatus.loading:
        return [
          Text('AI 正在准备讲解，请稍候…', style: hintStyle),
        ];
      case PoemExplainStatus.streaming:
        // 流式接收中：实时渲染已到达段落，不含朗读入口（半截文本不朗读）。
        return [
          for (final paragraph in state.paragraphs) ...[
            Text(
              paragraph,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],
          Text('AI 正在逐句生成…', style: hintStyle),
        ];
      case PoemExplainStatus.ready:
        return [
          // 内容区可点击播放：复用折叠区的 _onTapSection 竞态/会话逻辑。
          InkWell(
            onTap: () => _onTapSection(
              (section: _sectionAiExplain, playText: state.fullText),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final paragraph in state.paragraphs) ...[
                  Text(
                    paragraph,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                ],
              ],
            ),
          ),
          Text('点击内容可朗读，再次点击停止。', style: hintStyle),
        ];
      case PoemExplainStatus.error:
        return [
          Text(
            state.message ?? 'AI 讲解生成失败，请稍后重试。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ];
      case PoemExplainStatus.unconfigured:
        return [
          Text(
            state.message ?? '还没有配置 AI 服务，配置后即可使用 AI 讲解。',
            style: hintStyle,
          ),
        ];
    }
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
