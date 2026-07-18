// lib/features/poem/poem_tab_page.dart
//
// 层级：features/poem
// 职责：诗词 Tab 主页 — 搜索面板 + 诗词列表。

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/widgets/poem_card.dart';

class PoemTabPage extends ConsumerStatefulWidget {
  const PoemTabPage({super.key});

  @override
  ConsumerState<PoemTabPage> createState() => _PoemTabPageState();
}

class _PoemTabPageState extends ConsumerState<PoemTabPage> {
  static const _gradeLabels = {
    1: '一年级',
    2: '二年级',
    3: '三年级',
    4: '四年级',
    5: '五年级',
    6: '六年级',
  };

  static const _statusLabels = <LearningStatus?, String>{
    null: '全部',
    LearningStatus.notStarted: '未开始',
    LearningStatus.learning: '学习中',
    LearningStatus.reviewing: '复习中',
    LearningStatus.mastered: '已掌握',
  };

  /// 搜索面板是否展开
  bool _panelOpen = false;

  // ---- 搜索面板本地状态（点击"搜索"才同步到 provider） ----
  final _searchController = TextEditingController();
  int? _localGrade;
  LearningStatus? _localStatus;
  String? _localAuthor;
  String? _localDynasty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 打开面板时，从 provider 读取当前筛选值填入本地状态。
  void _openPanel() {
    _searchController.text = ref.read(poemSearchQueryProvider);
    _localGrade = ref.read(selectedGradeProvider);
    _localStatus = ref.read(selectedStatusFilterProvider);
    _localAuthor = ref.read(selectedAuthorFilterProvider);
    _localDynasty = ref.read(selectedDynastyFilterProvider);
    setState(() => _panelOpen = true);
  }

  /// 关闭面板（取消，不修改 provider）。
  void _closePanel() {
    setState(() => _panelOpen = false);
  }

  /// 应用搜索（同步本地状态到 provider 并关闭面板）。
  void _applySearch() {
    ref.read(poemSearchQueryProvider.notifier).state =
        _searchController.text.trim();
    ref.read(selectedGradeProvider.notifier).state = _localGrade;
    ref.read(selectedStatusFilterProvider.notifier).state = _localStatus;
    ref.read(selectedAuthorFilterProvider.notifier).state = _localAuthor;
    ref.read(selectedDynastyFilterProvider.notifier).state = _localDynasty;
    setState(() => _panelOpen = false);
  }

  /// 清空全部筛选条件。
  void _clearAll() {
    _searchController.clear();
    setState(() {
      _localGrade = null;
      _localStatus = null;
      _localAuthor = null;
      _localDynasty = null;
    });
  }

  /// 当前 provider 中是否有任何筛选生效。
  bool get _hasActiveFilters {
    return ref.watch(poemSearchQueryProvider).isNotEmpty ||
        ref.watch(selectedGradeProvider) != null ||
        ref.watch(selectedStatusFilterProvider) != null ||
        ref.watch(selectedAuthorFilterProvider) != null ||
        ref.watch(selectedDynastyFilterProvider) != null;
  }

  @override
  Widget build(BuildContext context) {
    final poems = ref.watch(filteredPoemsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _responsiveColumns(constraints.maxWidth);
          return CustomScrollView(
            slivers: [
              // ============ AppBar（精简版） ============
              SliverAppBar(
                floating: true,
                snap: true,
                automaticallyImplyLeading: false,
                leading: IconButton(
                  onPressed: () =>
                      context.push(AppRoutes.poemLearningPath),
                  icon: const Icon(Icons.route_rounded),
                  tooltip: '学习路径',
                ),
                title: const Text('诗词'),
                actions: [
                  IconButton(
                    onPressed: () =>
                        context.push(AppRoutes.poemFavorites),
                    icon: const Icon(Icons.favorite_border),
                    tooltip: '我的收藏',
                  ),
                  IconButton(
                    onPressed: _panelOpen ? _closePanel : _openPanel,
                    icon: Badge(
                      isLabelVisible: _hasActiveFilters && !_panelOpen,
                      child: Icon(
                        _panelOpen ? Icons.search_off : Icons.search,
                      ),
                    ),
                    tooltip: '搜索筛选',
                  ),
                ],
              ),

              // ============ 可收起搜索面板 ============
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _panelOpen
                      ? _buildSearchPanel(context)
                      : const SizedBox.shrink(),
                ),
              ),

              // ============ 诗词列表 ============
              if (poems.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: SpacingTokens.md),
                        Text(
                          '暂无诗词',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                    vertical: SpacingTokens.sm,
                  ).copyWith(bottom: 100),
                  sliver: SliverGrid(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: SpacingTokens.sm,
                      mainAxisSpacing: SpacingTokens.sm,
                      mainAxisExtent: 140,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final poem = poems[index];
                        final isFav =
                            ref.watch(isFavoriteProvider(poem.id));
                        final progress =
                            ref.watch(poemProgressProvider(poem.id));
                        return PoemCard(
                          poem: poem,
                          isFavorite: isFav,
                          learningStatus: progress?.status,
                          onTap: () {
                            context.push(
                              AppRoutes.poemDetailOf(poem.id),
                            );
                          },
                        )
                            .animate()
                            .fadeIn(
                              delay: (80 * index).ms,
                              duration: 300.ms,
                            )
                            .slideX(
                              begin: 0.1,
                              end: 0,
                              delay: (80 * index).ms,
                              duration: 300.ms,
                            );
                      },
                      childCount: poems.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------
  // 搜索面板
  // ----------------------------------------------------------------

  Widget _buildSearchPanel(BuildContext context) {
    final theme = Theme.of(context);
    final authors = ref.watch(availableAuthorsProvider);
    final dynasties = ref.watch(availableDynastiesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.md,
        vertical: SpacingTokens.sm,
      ),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- 搜索输入 ----
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索诗词…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      SpacingTokens.radiusPill,
                    ),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.sm,
                  ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: SpacingTokens.md),

              // ---- 筛选项（一行四个） ----
              Row(
                children: [
                  Expanded(
                    child: _buildDropdownTile(
                      theme: theme,
                      label: '状态',
                      value: _statusLabels[_localStatus] ?? '全部',
                      onTap: () => _showStatusSheet(),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(
                    child: _buildDropdownTile(
                      theme: theme,
                      label: '年级',
                      value: _localGrade == null
                          ? '全部'
                          : _gradeLabels[_localGrade] ?? '$_localGrade',
                      onTap: () => _showGradeSheet(),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(
                    child: _buildDropdownTile(
                      theme: theme,
                      label: '作者',
                      value: _localAuthor ?? '全部',
                      onTap: () => _showPickerSheet(
                        title: '选择作者',
                        current: _localAuthor,
                        items: authors,
                        allLabel: '全部作者',
                        onChanged: (v) =>
                            setState(() => _localAuthor = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(
                    child: _buildDropdownTile(
                      theme: theme,
                      label: '朝代',
                      value: _localDynasty ?? '全部',
                      onTap: () => _showPickerSheet(
                        title: '选择朝代',
                        current: _localDynasty,
                        items: dynasties,
                        allLabel: '全部朝代',
                        onChanged: (v) =>
                            setState(() => _localDynasty = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.lg),

              // ---- 操作按钮 ----
              Row(
                children: [
                  // 清空按钮（有任何本地筛选时显示）
                  if (_hasLocalFilters)
                    TextButton(
                      onPressed: _clearAll,
                      child: const Text('清空'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _closePanel,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  FilledButton.icon(
                    onPressed: _applySearch,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('搜索'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 本地筛选是否有任何非默认值。
  bool get _hasLocalFilters =>
      _searchController.text.isNotEmpty ||
      _localGrade != null ||
      _localStatus != null ||
      _localAuthor != null ||
      _localDynasty != null;

  /// 作者/朝代的可点击选择行。
  Widget _buildDropdownTile({
    required ThemeData theme,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.sm,
          vertical: SpacingTokens.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // 筛选 Sheet
  // ----------------------------------------------------------------

  void _showStatusSheet() {
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
              children: [
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '筛选学习状态',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<LearningStatus?>(
                      groupValue: _localStatus,
                      onChanged: (v) {
                        setState(() => _localStatus = v);
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _statusLabels.entries.map((e) {
                          return RadioListTile<LearningStatus?>(
                            title: Text(e.value),
                            value: e.key,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showGradeSheet() {
    final grades = ref.read(availableGradesProvider);
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
              children: [
                const SizedBox(height: SpacingTokens.md),
                Text(
                  '选择年级',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<int?>(
                      groupValue: _localGrade,
                      onChanged: (v) {
                        setState(() => _localGrade = v);
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RadioListTile<int?>(
                            title: Text('全部'),
                            value: null,
                          ),
                          ...grades.map((g) {
                            return RadioListTile<int?>(
                              title: Text(_gradeLabels[g] ?? '$g 年级'),
                              value: g,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 通用 String 选择 Sheet（作者 / 朝代）。

  void _showPickerSheet({
    required String title,
    required String? current,
    required List<String> items,
    required String allLabel,
    required ValueChanged<String?> onChanged,
  }) {
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
              children: [
                const SizedBox(height: SpacingTokens.md),
                Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<String?>(
                      groupValue: current,
                      onChanged: (v) {
                        onChanged(v);
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String?>(
                            title: Text(allLabel),
                            value: null,
                          ),
                          ...items.map((item) {
                            return RadioListTile<String?>(
                              title: Text(item),
                              value: item,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 根据可用宽度计算列数。
  static int _responsiveColumns(double width) {
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }
}
