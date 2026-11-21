import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_adventure_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/features/math/adventure/adventure_artwork.dart';
import 'package:poemath/features/math/adventure/adventure_navigation_bar.dart';
import 'package:poemath/features/math/adventure/adventure_region_scene.dart';
import 'package:poemath/features/math/adventure/math_adventure_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

Widget adventureReadError(WidgetRef ref) => AppScaffold(
  appBar: AppBar(title: const Text('数学探险')),
  body: Center(
    child: Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppEmptyState(
            icon: Icons.explore_outlined,
            title: '旅途记录暂时打不开',
            description: '稍后再试，就能接着探索。',
          ),
          FilledButton.icon(
            onPressed: () {
              ref.invalidate(mathAdventureRepositoryProvider);
              ref.invalidate(mathAdventureProgressProvider);
              ref.invalidate(mathAdventureReconcileProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重新打开'),
          ),
        ],
      ),
    ),
  ),
);

class MathAdventureEntry extends ConsumerWidget {
  const MathAdventureEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '数学探险，进入大陆地图',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.appearance.cardRadius),
        child: ColoredCard(
          color: scheme.surface,
          backgroundOpacity: 1,
          padding: EdgeInsets.zero,
          onTap: () => context.push(AppRoutes.mathAdventure),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: theme.appearance.playful ? .38 : 1,
                    heightFactor: 1,
                    child: Padding(
                      padding: theme.appearance.playful
                          ? const EdgeInsets.all(SpacingTokens.sm)
                          : EdgeInsets.zero,
                      child: Image.asset(
                        theme.appearance.adventureImage,
                        alignment: Alignment.centerRight,
                        fit: theme.appearance.playful
                            ? BoxFit.contain
                            : BoxFit.cover,
                        color: theme.appearance.pine ? scheme.onSurface : null,
                        opacity: theme.appearance.pine
                            ? AlwaysStoppedAnimation(
                                theme.brightness == Brightness.dark ? .3 : .6,
                              )
                            : theme.appearance.ochre
                            ? AlwaysStoppedAnimation(
                                theme.brightness == Brightness.dark ? .4 : .8,
                              )
                            : null,
                        cacheWidth: 1024,
                      ),
                    ),
                  ),
                ),
              ),
              if (!theme.appearance.playful)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.surface,
                          scheme.surface.withValues(alpha: .96),
                          scheme.surface.withValues(alpha: .15),
                        ],
                        stops: const [0, .6, 1],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: theme.appearance.playful ? .62 : .7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('数学探险', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: SpacingTokens.sm),
                        Text('下一站，会遇见什么？', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: SpacingTokens.md),
                        Text(
                          '打开地图  →',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
}

class MathAdventurePage extends ConsumerStatefulWidget {
  const MathAdventurePage({super.key});
  @override
  ConsumerState<MathAdventurePage> createState() => _MathAdventurePageState();
}

class _MathAdventurePageState extends ConsumerState<MathAdventurePage> {
  final _anchors = <String, GlobalKey>{};
  final _regionAnchors = <MathAdventureRegion, GlobalKey>{};
  final _viewportKey = GlobalKey();
  final _completionKey = GlobalKey();
  final _scrollController = ScrollController();
  List<MathAdventureRegion> _regions = const [];
  MathAdventureRegion? _visibleRegion;
  double _navigationExtent = 0;
  bool _regionSyncScheduled = false;
  bool _opening = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  CustomClipper<Rect> _foregroundClipper(GlobalKey key) =>
      _AdventureForegroundClipper(
        viewportKey: _viewportKey,
        contentKey: key,
        navigationExtent: _navigationExtent,
        scroll: _scrollController,
      );

  void _scheduleRegionSync() {
    if (_regionSyncScheduled) return;
    _regionSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _regionSyncScheduled = false;
      if (!mounted || _regions.isEmpty) return;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      var visible = _regions.first;
      for (final region in _regions) {
        final box = _regionAnchors[region]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top <= _navigationExtent + SpacingTokens.lg) visible = region;
      }
      // A short final region may never reach the navigation's lower edge.
      // At the end of the route its title must still become visible.
      if (_scrollController.hasClients &&
          _scrollController.position.pixels > 0 &&
          _scrollController.position.extentAfter == 0) {
        visible = _regions.last;
      }
      if (visible != _visibleRegion) setState(() => _visibleRegion = visible);
    });
  }

  Future<void> _open(MathSkill skill) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final settings = ref.read(mathAdventureSettingsProvider);
      final node = MathAdventureNode(
        grade: settings.grade,
        semester: settings.semester,
        skillId: skill.id,
      );
      ref
          .read(mathAdventureRepositoryProvider)
          .assertCanStart(node, settings.difficulty);
      await context.push(
        AppRoutes.mathAdventurePracticeOf(
          node.grade,
          node.semester,
          node.skillId,
          fromMap: true,
        ),
      );
      if (mounted) ref.invalidate(mathAdventureReconcileProvider);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('小路状态有变化，请重新选择当前关卡')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _locate(MathSkill skill) {
    final target = _anchors[skill.id]?.currentContext;
    if (target == null) return;
    final render = target.findRenderObject();
    if (render == null) return;
    final position = Scrollable.of(target).position;
    // The transparent navigation overlays the viewport; reveal the waypoint
    // below it, including when jumping across regions or using larger text.
    final offset =
        (RenderAbstractViewport.of(render).getOffsetToReveal(render, 0).offset -
                _navigationExtent -
                SpacingTokens.md)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    final animate =
        ref.read(pageAnimationsEnabledProvider) &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate) {
      position.animateTo(
        offset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      position.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(mathAdventureSettingsProvider);
    final profile = ref.watch(mathAdventureProfileProvider).id;
    final reconciliation = ref.watch(mathAdventureReconcileProvider);
    final records = ref.watch(mathAdventureProgressProvider);
    if (records.hasError) return adventureReadError(ref);
    final all = records.requireValue;
    final progress =
        all
            .where(
              (p) =>
                  p.grade == settings.grade && p.semester == settings.semester,
            )
            .firstOrNull ??
        MathAdventureProgress(
          profileId: profile,
          grade: settings.grade,
          semester: settings.semester,
        );
    final regions = MathAdventureCatalog.regions(
      grade: settings.grade,
      semester: settings.semester,
      difficulty: settings.difficulty,
    );
    final route = regions.values.expand((s) => s).toList();
    final current = MathAdventureCatalog.current(
      route,
      progress.completedSkillIds,
    );
    final souvenirs = MathAdventureRegion.values.where(
      (r) => progress.collectedRegionIds.contains(r.id),
    );
    _regions = regions.keys.toList();
    _scheduleRegionSync();
    final navigation = AdventureNavigationBar(
      context: context,
      region: regions.containsKey(_visibleRegion)
          ? _visibleRegion
          : regions.keys.firstOrNull,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.mathTab);
        }
      },
      onAlbum: () => context.push(AppRoutes.mathAdventureAlbum),
      onLocate: current == null ? null : () => _locate(current),
    );
    _navigationExtent =
        navigation.preferredSize.height + MediaQuery.paddingOf(context).top;
    final collection = souvenirs.isNotEmpty || reconciliation.hasError
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (souvenirs.isNotEmpty)
                  Wrap(
                    spacing: SpacingTokens.sm,
                    runSpacing: SpacingTokens.sm,
                    children: [
                      for (final region in souvenirs)
                        ActionChip(
                          avatar: AdventureSouvenir(region: region),
                          label: Text('已获得 · ${region.souvenir}'),
                          onPressed: () =>
                              context.push(AppRoutes.mathAdventureAlbum),
                        ),
                    ],
                  ),
                if (reconciliation.hasError)
                  AppTile(
                    icon: Icons.refresh,
                    iconColor: theme.colorScheme.error,
                    title: '纪念物暂未保存',
                    subtitle: '旅途记录已保留，点击重试',
                    onTap: () => ref.invalidate(mathAdventureReconcileProvider),
                  ),
              ],
            ),
          )
        : null;
    return AppScaffold(
      extendBodyBehindAppBar: true,
      appBar: navigation,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox.expand(
            child: Stack(
              key: _viewportKey,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0) _scheduleRegionSync();
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    key: PageStorageKey(
                      'adventure:$profile:${settings.grade}:${settings.semester}',
                    ),
                    padding: const EdgeInsets.only(bottom: SpacingTokens.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (route.isEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: _navigationExtent),
                            child: Column(
                              children: [
                                ?collection,
                                const AppEmptyState(
                                  icon: Icons.explore_outlined,
                                  title: '这片小路正在准备',
                                  description: '当前学习背景暂时没有可探索的知识点。',
                                ),
                              ],
                            ),
                          ),
                        for (final (index, entry) in regions.entries.indexed)
                          AdventureRegionScene(
                            key: _regionAnchors.putIfAbsent(
                              entry.key,
                              GlobalKey.new,
                            ),
                            foregroundClipper: _foregroundClipper(
                              _regionAnchors[entry.key]!,
                            ),
                            topInset: index == 0 ? _navigationExtent : 0,
                            leading: index == 0 ? collection : null,
                            region: entry.key,
                            skills: entry.value,
                            current: current,
                            completed: progress.completedSkillIds,
                            collected: progress.collectedRegionIds.contains(
                              entry.key.id,
                            ),
                            busy: _opening,
                            startIndex: route.indexOf(entry.value.first),
                            anchorFor: (skill) =>
                                _anchors.putIfAbsent(skill.id, GlobalKey.new),
                            onSelect: _open,
                            onAlbum: () =>
                                context.push(AppRoutes.mathAdventureAlbum),
                          ),
                        if (current == null && route.isNotEmpty)
                          ClipRect(
                            key: _completionKey,
                            clipper: _foregroundClipper(_completionKey),
                            child: ColoredCard(
                              color: theme.colorScheme.primary,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.flag_rounded,
                                    size: SpacingTokens.xxl,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(height: SpacingTokens.sm),
                                  Text(
                                    '本册探索完成！',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: SpacingTokens.sm),
                                  const Text(
                                    '每一站都留下了你的脚印。点亮的小路，随时欢迎你再来。',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: SpacingTokens.md),
                                  FilledButton.tonal(
                                    onPressed: () => context.push(
                                      AppRoutes.mathAdventureAlbum,
                                    ),
                                    child: const Text('翻开纪念册'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // A soft wash preserves contrast while the terrain remains
                // visible through the transparent navigation, with no hard edge.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _navigationExtent + SpacingTokens.xxl,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: ColoredCard(
                        borderRadius: BorderRadius.zero,
                        padding: EdgeInsets.zero,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.surface.withValues(alpha: .8),
                            theme.colorScheme.surface.withValues(alpha: .8),
                            theme.colorScheme.surface.withValues(alpha: 0),
                          ],
                          stops: [
                            0,
                            _navigationExtent /
                                (_navigationExtent + SpacingTokens.xxl),
                            1,
                          ],
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keep labels, paths and tap targets below the navigation while the terrain
/// scrolls all the way behind it. Reclip on scroll without rebuilding the map.
class _AdventureForegroundClipper extends CustomClipper<Rect> {
  _AdventureForegroundClipper({
    required this.viewportKey,
    required this.contentKey,
    required this.navigationExtent,
    required Listenable scroll,
  }) : super(reclip: scroll);

  final GlobalKey viewportKey, contentKey;
  final double navigationExtent;

  @override
  Rect getClip(Size size) {
    final viewport = viewportKey.currentContext?.findRenderObject();
    final content = contentKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || content is! RenderBox) {
      return Offset.zero & size;
    }
    final top = content.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return Rect.fromLTRB(
      0,
      (navigationExtent - top).clamp(0, size.height),
      size.width,
      size.height,
    );
  }

  @override
  Rect getApproximateClipRect(Size size) => getClip(size);

  // Content above a scene can change height without resizing this scene.
  @override
  bool shouldReclip(_AdventureForegroundClipper oldClipper) => true;
}
