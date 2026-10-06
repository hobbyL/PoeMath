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
  late final TtsService _tts;
  bool _isSpeaking = false;

  /// 点击可播区域后 → 首段音频就绪前的遮罩期，拦截一切重复点击。
  bool _isPreparing = false;

  /// 当前播放区域：-1 无 / 0 正文 / 1..5 折叠区（见 _Section 常量）。
  int _activeSection = -1;

  /// 当前正在朗读的行索引，-1 表示未朗读。
  int _currentLineIndex = -1;

  /// 播放会话代际令牌（竞态防护）。
  ///
  /// 场景：切换区域时「先 stop 再播」——旧朗读的 Future 可能在新区域
  /// 已开始播放后才被引擎唤醒，其 finally/onLineStart 会把新区域的
  /// 播放态错误复位。每次 stop / 新播放都递增代际，过期会话的回调
  /// 不再触碰页面状态。
  int _speakGeneration = 0;

  /// 区域编号常量：正文为 0，折叠区 1..5。
  static const int _sectionContent = 0;
  static const int _sectionTranslation = 1;
  static const int _sectionAnnotations = 2;
  static const int _sectionAppreciation = 3;
  static const int _sectionBackground = 4;
  static const int _sectionFamousLines = 5;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
  }

  @override
  void dispose() {
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
  /// - 点击正在朗读的区域：仅停止
  /// - 朗读中点击其他区域：停止当前并播放新区域
  /// - 空闲点击：播放该区域
  Future<void> _onTapSection(int section, String text) async {
    if (_isPreparing) return;
    if (_isSpeaking && _activeSection == section) {
      await _stopSpeaking();
      return;
    }
    if (_isSpeaking) {
      await _stopSpeaking();
    }
    if (!mounted) return;
    await _startSpeak(section, text);
  }

  /// 停止当前朗读并清理全部播放态。
  Future<void> _stopSpeaking() async {
    _speakGeneration++; // 使旧会话的回调全部失效
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
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _currentLineIndex = -1;
          _activeSection = -1;
        });
      }
    }
  }

  /// 播放指定区域：正文（section 0）逐行朗读 + 当前行高亮；
  /// 折叠区按标点分句朗读，不做逐行高亮。
  Future<void> _startSpeak(int section, String text) async {
    _speakGeneration++;
    final generation = _speakGeneration;
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      _isPreparing = true;
      _isSpeaking = true;
      _activeSection = section;
    });
    try {
      if (section == _sectionContent) {
        final lines = _splitLines(text);
        await _tts.speakLines(
          lines,
          onLineStart: (index) {
            if (mounted && generation == _speakGeneration) {
              setState(() => _currentLineIndex = index);
            }
          },
          onReady: () {
            if (mounted && generation == _speakGeneration) {
              setState(() => _isPreparing = false);
            }
          },
        );
      } else {
        await _tts.speakSentences(
          text,
          onReady: () {
            if (mounted && generation == _speakGeneration) {
              setState(() => _isPreparing = false);
            }
          },
        );
      }
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '诗词朗读失败',
        tag: 'PoemDetail',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && generation == _speakGeneration) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(
            content: Text('朗读失败，请检查系统语音服务后重试'),
          ),
        );
      }
    } finally {
      // 兜底清理：异常路径下 onReady 可能未触发，遮罩不允许卡死。
      // 过期代际（已被 stop/新会话接管）不清理，避免复位新会话的状态。
      if (mounted && generation == _speakGeneration) {
        setState(() {
          _isPreparing = false;
          _isSpeaking = false;
          _currentLineIndex = -1;
          _activeSection = -1;
        });
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
                onTap: () => _onTapSection(_sectionContent, poem.content),
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
                  section: _sectionTranslation,
                  playText: poem.translation,
                  child: _buildPlayableChild(
                    _sectionTranslation,
                    poem.translation,
                    Text(
                      poem.translation,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
                    ),
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
                  section: _sectionAnnotations,
                  playText: annotationsText,
                  child: _buildPlayableChild(
                    _sectionAnnotations,
                    annotationsText,
                    _buildAnnotationsList(context, poem),
                  ),
                ),
              ],

              // 赏析
              if (poem.appreciation.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.md),
                _buildCollapsibleSection(
                  context,
                  icon: Icons.local_florist_outlined,
                  title: '赏析',
                  section: _sectionAppreciation,
                  playText: poem.appreciation,
                  child: _buildPlayableChild(
                    _sectionAppreciation,
                    poem.appreciation,
                    Text(
                      poem.appreciation,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
                    ),
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
                  section: _sectionBackground,
                  playText: poem.background,
                  child: _buildPlayableChild(
                    _sectionBackground,
                    poem.background,
                    Text(
                      poem.background,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
                    ),
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
                    Text(
                      '语音合成中…',
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
  /// [section] / [playText] 提供时，展开后的内容区域可点击播放该文本，
  /// 播放中在标题旁显示 graphic_eq 小图标（不参与点击的作者简介等不传）。
  Widget _buildCollapsibleSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
    int? section,
    String? playText,
  }) {
    final theme = Theme.of(context);
    final playing = section != null &&
        _isSpeaking &&
        _activeSection == section;
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
          children: [child],
        ),
      ),
    );
  }

  /// 折叠区展开内容：包裹 InkWell 使内容区域可点击播放。
  ///
  /// 仅包内容 child，不包标题行——折叠态点击标题仍走展开/收起。
  Widget _buildPlayableChild(int section, String playText, Widget child) {
    return InkWell(
      onTap: () => _onTapSection(section, playText),
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
      section: _sectionFamousLines,
      playText: playText,
      child: _buildPlayableChild(
        _sectionFamousLines,
        playText,
        Column(
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
