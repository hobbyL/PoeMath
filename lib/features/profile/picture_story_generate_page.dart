import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/services/picture_story_generation_controller.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/picture_story_generation_draft.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/profile/picture_story_candidate_editor_page.dart';

class PictureStoryGeneratePage extends ConsumerStatefulWidget {
  const PictureStoryGeneratePage({super.key});
  @override
  ConsumerState<PictureStoryGeneratePage> createState() =>
      _PictureStoryGeneratePageState();
}

class _PictureStoryGeneratePageState
    extends ConsumerState<PictureStoryGeneratePage>
    with WidgetsBindingObserver {
  late final PictureStoryGenerationService _service;
  late final PictureStoryGenerationController _controller;
  late final String _profile;
  late final int _profileRevision;
  final _requirements = TextEditingController();
  final _themes = <String>{'日常生活'};
  int _count = 3;
  int _publicationToken = 0;
  bool _foreground = true;
  bool _publishing = false;
  PictureStoryRunState get _run => _controller.stateFor(_profile);
  bool get _busy => _publishing || _run.isBusy || _service.isRunning(_profile);
  bool get _generating => _run.isBusy;
  String get _generationStatus => _run.progress;
  PictureStoryGenerationDraft? _draft;
  String? _error;
  bool _loadFailed = false;
  StreamSubscription<String>? _profileChanges;
  bool get _sameProfile =>
      ProfileScope.currentId == _profile &&
      ProfileScope.revision == _profileRevision;

  @override
  void initState() {
    super.initState();
    _profile = ProfileScope.currentId;
    _profileRevision = ProfileScope.revision;
    _service = ref.read(pictureStoryGenerationServiceProvider);
    _controller = ref.read(pictureStoryGenerationControllerProvider);
    _controller.addListener(_reload);
    _reload(notify: false);
    WidgetsBinding.instance.addObserver(this);
    ParentAccessService.instance.addListener(_parentChanged);
    _profileChanges = ProfileScope.changes.listen((_) {
      _invalidatePage();
    });
  }

  void _reload({bool notify = true}) {
    try {
      final draft = _service.readDraft(_profile);
      _draft = draft;
      final options = draft?.options ?? (_run.isBusy ? _run.options : null);
      if (options != null && (draft?.candidates.isEmpty ?? true)) {
        _count = options.count;
        _themes
          ..clear()
          ..addAll(options.themes);
        if (_requirements.text != options.requirements) {
          _requirements.text = options.requirements;
        }
      }
      _loadFailed = false;
    } on Object {
      _loadFailed = true;
      _error = '生成草稿暂时无法读取，请检查本地存储后重试';
    }
    if (notify && mounted) setState(() {});
  }

  void _parentChanged() {
    if (!ParentAccessService.instance.isUnlocked) _invalidatePage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidatePage();
  }

  void _invalidatePage() {
    _publicationToken++;
    if (mounted) setState(() {});
  }

  void _pause() => _controller.pause(_profile);

  bool _canPublish(int token) =>
      mounted &&
      _foreground &&
      _sameProfile &&
      token == _publicationToken &&
      ParentAccessService.instance.isUnlocked &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  Future<void> _generate({
    String? candidateId,
    String? reuseImageId,
    bool regenerate = false,
  }) {
    if (_busy || !_sameProfile) return Future<void>.value();
    setState(() => _error = null);
    return _controller.start(
      profileId: _profile,
      profileRevision: _profileRevision,
      options:
          _draft?.options ??
          PictureStoryGenerationOptions(
            level: PictureStoryLevel.starter,
            count: _count,
            themes: _themes.toList(),
            requirements: _requirements.text.trim(),
          ),
      candidateId: candidateId,
      reuseImageId: reuseImageId,
      regenerateImage: regenerate,
    );
  }

  Future<void> _regenerate(PictureStoryGenerationCandidate item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新生成这道题？'),
        content: const Text('将替换当前草稿的图片和已编辑内容，并再次使用生图和大模型额度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _generate(candidateId: item.id, regenerate: true);
    }
  }

  Future<void> _edit(PictureStoryGenerationCandidate item) async {
    if (_busy || _draft == null) return;
    try {
      final session = await _service.beginEdit(_draft!, item.id);
      if (!mounted ||
          !_sameProfile ||
          !ParentAccessService.instance.isUnlocked) {
        return;
      }
      await Navigator.push<void>(
        context,
        fadeSlideRoute(
          builder: (_) => ParentAccessBoundary(
            child: PictureStoryCandidateEditorPage(
              service: _service,
              session: session,
            ),
          ),
        ),
      );
      if (mounted) _reload();
    } on Object {
      if (mounted) setState(() => _error = '草稿暂时无法编辑，请重试');
    }
  }

  Future<void> _select(
    PictureStoryGenerationCandidate item,
    bool selected,
  ) async {
    try {
      await _service.setSelected(_draft!, item.id, selected);
      if (mounted) _reload();
    } on Object {
      if (mounted) setState(() => _error = '选择暂未保存，请重试');
    }
  }

  Future<void> _publish() async {
    if (_busy || _draft == null) return;
    final token = ++_publicationToken;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final authorize = ParentAccessService.instance.captureAuthorization();
      final count = await _service.publish(
        _draft!,
        check: () {
          authorize();
          if (!_canPublish(token)) throw const ParentAccessDenied();
        },
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已入库 $count 道题，并为当前孩子启用')));
      if (_draft == null) {
        _controller.clearStatus(_profile);
        context.pop();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : error is PictureStoryPublicationCleanupException
              ? error.toString()
              : '题目暂未入库，草稿仍保留，请重试',
        );
      }
    } finally {
      if (mounted) {
        _publishing = false;
        _reload();
      }
    }
  }

  Future<void> _discard() async {
    final draft = _draft;
    if (draft == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃生成草稿？'),
        content: const Text('未入库的题目与修改将从本次草稿中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃草稿'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.discardDraft(draft);
      _controller.clearStatus(_profile);
      if (mounted) _reload();
    } on Object {
      if (mounted) setState(() => _error = '草稿暂时无法移除，请重试');
    }
  }

  @override
  void dispose() {
    _publicationToken++;
    _controller.removeListener(_reload);
    WidgetsBinding.instance.removeObserver(this);
    ParentAccessService.instance.removeListener(_parentChanged);
    unawaited(_profileChanges?.cancel());
    _requirements.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _draft;
    final hasCandidates = draft?.candidates.isNotEmpty ?? false;
    final canOperate = !_busy && _sameProfile && !_loadFailed;
    final selectedCount = draft?.selectedPrompts.length ?? 0;
    final error = _error ?? _run.message;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 看图说话出题'),
        actions: [
          if (draft != null)
            IconButton(
              tooltip: '放弃草稿',
              icon: const Icon(Icons.delete_outline),
              onPressed: canOperate ? _discard : null,
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedPageBody(
            children: [
              if (!_sameProfile) ...[
                Text(
                  '孩子档案已切换，请返回题库后重新进入。',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
              if (error != null) ...[
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
                if (_loadFailed)
                  TextButton(
                    onPressed: () => _reload(),
                    child: const Text('重试读取草稿'),
                  ),
                const SizedBox(height: SpacingTokens.md),
              ],
              if (draft != null || _generating) ...[
                if (_busy)
                  LinearProgressIndicator(
                    semanticsLabel: _generating ? '正在生成题目' : '正在入库',
                  ),
                if (_generating)
                  Wrap(
                    spacing: SpacingTokens.sm,
                    children: [
                      TextButton.icon(
                        onPressed: _run.phase == PictureStoryRunPhase.stopping
                            ? null
                            : _pause,
                        icon: const Icon(Icons.pause),
                        label: Text(
                          _run.phase == PictureStoryRunPhase.stopping
                              ? '正在暂停生成…'
                              : '暂停生成',
                        ),
                      ),
                    ],
                  ),
                if (_busy) const SizedBox(height: SpacingTokens.md),
              ],
              if (_generating || !hasCandidates) ...[
                const Text('离开此页仍会继续生成；切到后台或锁屏会暂停。'),
                const SizedBox(height: SpacingTokens.md),
              ],
              if (!hasCandidates && !_loadFailed) _options(theme, canOperate),
              if (draft != null && hasCandidates)
                MasonryLayout(
                  key: const ValueKey('picture-story-generation-masonry'),
                  columnCount: ResponsiveLayout.columns(constraints.maxWidth),
                  gap: SpacingTokens.md,
                  children: [
                    for (final (index, item) in draft.candidates.indexed)
                      _candidate(theme, item, index, canOperate),
                  ],
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: !hasCandidates
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                child: FilledButton(
                  onPressed: canOperate && selectedCount > 0 ? _publish : null,
                  child: Text(_busy ? '请稍候…' : '确认入库（$selectedCount 道）'),
                ),
              ),
            ),
    );
  }

  Widget _options(ThemeData theme, bool enabled) {
    final hasPendingPlan = _draft != null;
    final canEdit = enabled && !hasPendingPlan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasPendingPlan && !_busy) ...[
          Text(
            '上次生成未完成，出题要求已保留。可重试生成，或先放弃草稿再修改要求。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
        ],
        Text('生成内容', style: theme.textTheme.titleMedium),
        const SizedBox(height: SpacingTokens.sm),
        const Text('每道题一张图，每次可生成 1–5 道。先生成图片，再根据实际画面编写问题。'),
        const SizedBox(height: SpacingTokens.md),
        Text('数量（$_count 题）', style: theme.textTheme.titleSmall),
        Slider(
          value: _count.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          label: '$_count',
          semanticFormatterCallback: (value) => '${value.round()} 题',
          onChanged: canEdit
              ? (value) => setState(() => _count = value.round())
              : null,
        ),
        const SizedBox(height: SpacingTokens.md),
        const Text('主题（可多选）'),
        const SizedBox(height: SpacingTokens.xs),
        Wrap(
          spacing: SpacingTokens.xs,
          runSpacing: SpacingTokens.xs,
          children: [
            for (final theme in PictureStoryGenerationOptions.availableThemes)
              FilterChip(
                label: Text(theme),
                selected: _themes.contains(theme),
                onSelected: canEdit
                    ? (v) {
                        setState(() {
                          if (v) {
                            _themes.add(theme);
                          } else {
                            _themes.remove(theme);
                          }
                        });
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
        TextField(
          controller: _requirements,
          enabled: canEdit,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: '补充要求（选填）',
            hintText: '例如：雨天互相帮助，画面里有小动物',
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        FilledButton.icon(
          onPressed: enabled ? () => _generate() : null,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(
            _busy
                ? _generationStatus
                : hasPendingPlan
                ? '重试生成图文题目'
                : '生成图文题目',
          ),
        ),
      ],
    );
  }

  Widget _candidate(
    ThemeData theme,
    PictureStoryGenerationCandidate item,
    int index,
    bool enabled,
  ) {
    final edit = item.edit;
    final published = item.stage == PictureStoryGenerationStage.published;
    final interrupted =
        !_generating &&
        (item.stage == PictureStoryGenerationStage.generatingImage ||
            item.stage == PictureStoryGenerationStage.generatingText);
    final stageLabel = interrupted ? '生成已中断，可重试' : item.stage.label;
    // 图形居中在完整点击区域内，标题行需补偿其内置的水平留白。
    const checkboxInset = (kMinInteractiveDimension - Checkbox.width) / 2;
    return ColoredCard(
      key: ValueKey(item.id),
      color: theme.colorScheme.primary,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (edit.image != null)
            PictureStoryImageView(
              image: edit.image!,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SpacingTokens.radiusMedium),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              left: SpacingTokens.md,
              top: SpacingTokens.md,
              right: item.isReady
                  ? SpacingTokens.md - checkboxInset
                  : SpacingTokens.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text:
                          edit.fields[PictureStoryEditorField.title]
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? edit.fields[PictureStoryEditorField.title]!
                          : '第 ${index + 1} 道题',
                      children: [
                        TextSpan(
                          text: ' $stageLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
                if (item.isReady)
                  Checkbox(
                    value: item.selected,
                    semanticLabel: '选择第 ${index + 1} 道题',
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.standard,
                    onChanged: enabled
                        ? (v) => _select(item, v ?? false)
                        : null,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: SpacingTokens.md,
              right: SpacingTokens.md,
              bottom: SpacingTokens.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (edit.fields[PictureStoryEditorField.theme]
                        ?.trim()
                        .isNotEmpty ==
                    true)
                  Text(
                    edit.fields[PictureStoryEditorField.theme]!,
                    style: theme.textTheme.bodySmall,
                  ),
                if (item.isReady ||
                    published ||
                    item.stage == PictureStoryGenerationStage.needsEditing) ...[
                  for (final (field, label) in [
                    (PictureStoryEditorField.questions, '引导问题'),
                    (PictureStoryEditorField.sceneFacts, '观察提示'),
                    (PictureStoryEditorField.goals, '练习目标'),
                    (PictureStoryEditorField.reference, '参考表达'),
                  ])
                    if (edit.fields[field]?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: SpacingTokens.md),
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: TypographyTokens.fsSection,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Text(
                        edit.fields[field]!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                ],
                if (item.error != null) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    item.error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (!published)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: SpacingTokens.sm,
                    runSpacing: SpacingTokens.sm,
                    children: [
                      if (edit.image != null)
                        TextButton.icon(
                          onPressed: enabled ? () => _edit(item) : null,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑内容'),
                        ),
                      if (item.isReady ||
                          item.stage ==
                              PictureStoryGenerationStage.needsEditing)
                        TextButton.icon(
                          onPressed: enabled ? () => _regenerate(item) : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新生成'),
                        )
                      else
                        TextButton.icon(
                          onPressed: enabled
                              ? () => _generate(
                                  candidateId: item.id,
                                  reuseImageId: edit.image?.value,
                                )
                              : null,
                          icon: const Icon(Icons.refresh),
                          label: Text(edit.image == null ? '生成图片' : '重试出题'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
