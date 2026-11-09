import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/core/widgets/hero_starlight_painter.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';

enum AnimatedHeroStyle { aurora, starlight }

/// 页面顶部的主题色背景；深色主题使用深底，避免整片浅色刺眼。
@immutable
class AnimatedHeroColors {
  factory AnimatedHeroColors(
    ThemeData theme, {
    AnimatedHeroStyle style = AnimatedHeroStyle.aurora,
  }) {
    final dark = theme.brightness == Brightness.dark;
    final starlight = style == AnimatedHeroStyle.starlight;
    final scheme = theme.colorScheme;
    final accent = starlight
        ? Color.lerp(scheme.tertiary, ColorTokens.mathPurpleDeep, .66)!
        : scheme.primary;
    final shade = dark && !starlight ? scheme.surface : scheme.shadow;
    return AnimatedHeroColors._(
      foreground: dark ? scheme.onSurface : scheme.onPrimary,
      base: Color.lerp(
        accent,
        shade,
        starlight ? (dark ? .78 : .66) : (dark ? .9 : .14),
      )!,
      depth: Color.lerp(
        accent,
        shade,
        starlight ? (dark ? .92 : .86) : (dark ? .96 : .38),
      )!,
      glow: starlight
          ? Color.lerp(scheme.tertiaryContainer, ColorTokens.mathBlue, .6)!
          : scheme.tertiary,
    );
  }

  const AnimatedHeroColors._({
    required this.foreground,
    required this.base,
    required this.depth,
    required this.glow,
  });

  final Color foreground;
  final Color base;
  final Color depth;
  final Color glow;
}

/// 背景随滚动视差、下拉放大，前景保持原字号和命中区大小。
/// 可选择水波流光或星光轨道；与提醒按钮共用时钟，不可见或后台时停止。
class AnimatedHeroHeader extends StatefulWidget {
  const AnimatedHeroHeader({
    super.key,
    required this.scrollController,
    required this.child,
    this.animate = true,
    this.style = AnimatedHeroStyle.aurora,
    this.backgroundKey = const ValueKey('animated-hero-background'),
  });

  final ScrollController scrollController;
  final Widget child;
  final bool animate;
  final AnimatedHeroStyle style;
  final Key backgroundKey;

  @override
  State<AnimatedHeroHeader> createState() => _AnimatedHeroHeaderState();
}

class _AnimatedHeroHeaderState extends State<AnimatedHeroHeader>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: _motionDuration,
  );
  Duration get _motionDuration => widget.style == AnimatedHeroStyle.starlight
      ? const Duration(seconds: 16)
      : const Duration(seconds: 6);
  AppLifecycleState? _lifecycle;
  double _headerHeight = 0;
  bool _allowed = false;
  bool _currentRoute = true;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.scrollController.addListener(_refreshMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _allowed =
        !media.disableAnimations &&
        !media.accessibleNavigation &&
        TickerMode.valuesOf(context).enabled;
    _currentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    _refreshMotion();
  }

  @override
  void didUpdateWidget(AnimatedHeroHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_refreshMotion);
      widget.scrollController.addListener(_refreshMotion);
    }
    if (oldWidget.style != widget.style) {
      _motion.duration = _motionDuration;
      if (_active) _motion.repeat();
    }
    _refreshMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _refreshMotion();
  }

  void _refreshMotion() {
    final scroll = widget.scrollController;
    final active =
        widget.animate &&
        _allowed &&
        _currentRoute &&
        (_lifecycle == null || _lifecycle == AppLifecycleState.resumed) &&
        scroll.hasClients &&
        scroll.offset < _headerHeight;
    if (_active == active) return;
    setState(() => _active = active);
    if (active) {
      _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  void _updateHeight(double height) {
    if (_headerHeight == height) return;
    _headerHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshMotion();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.scrollController.removeListener(_refreshMotion);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = AnimatedHeroColors(Theme.of(context), style: widget.style);
    final reduceMotion = media.disableAnimations || media.accessibleNavigation;
    // 顶部是独立的动态区域，按产品约定直接展示动效；
    // 局部覆盖仅作用于本卡片，不受页面转场/入场开关影响。
    return PageAnimationScope(
      enabled: _allowed,
      child: _HeroMotion(
        animation: _motion,
        active: _active,
        child: Builder(
          builder: (context) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _updateHeight(constraints.maxHeight);
                        return AnimatedBuilder(
                          animation: widget.scrollController,
                          builder: (context, _) {
                            final scrollController = widget.scrollController;
                            final offset =
                                scrollController.hasClients && !reduceMotion
                                ? scrollController.offset
                                : 0.0;
                            final stretch = math.max(0.0, -offset);
                            final height = constraints.maxHeight;
                            // 底边锚定：下拉造成的整体下移被向上的放大抵消，
                            // 背景始终覆盖顶边；后续实色内容覆盖视差溢出部分。
                            return Transform.translate(
                              offset: Offset(
                                0,
                                offset.clamp(0.0, height) * .65,
                              ),
                              child: Transform.scale(
                                scale: 1 + stretch / height,
                                alignment: Alignment.bottomCenter,
                                child: AnnotatedRegion<SystemUiOverlayStyle>(
                                  value:
                                      colors.foreground.computeLuminance() > .5
                                      ? SystemUiOverlayStyle.light
                                      : SystemUiOverlayStyle.dark,
                                  child: RepaintBoundary(
                                    key: widget.backgroundKey,
                                    child: ColoredCard(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [colors.base, colors.depth],
                                      ),
                                      borderRadius: BorderRadius.zero,
                                      padding: EdgeInsets.zero,
                                      child:
                                          CustomPaint(
                                                painter:
                                                    widget.style ==
                                                        AnimatedHeroStyle
                                                            .starlight
                                                    ? HeroStarlightPainter(
                                                        base: colors.base,
                                                        depth: colors.depth,
                                                        foreground:
                                                            colors.foreground,
                                                        glow: colors.glow,
                                                        motion: _motion,
                                                        pull:
                                                            stretch /
                                                            (height + stretch),
                                                      )
                                                    : _HeroAuroraPainter(
                                                        base: colors.base,
                                                        depth: colors.depth,
                                                        foreground:
                                                            colors.foreground,
                                                        glow: colors.glow,
                                                        motion: _motion,
                                                        pull:
                                                            stretch /
                                                            (height + stretch),
                                                      ),
                                              )
                                              .animatePage(context)
                                              .fadeIn(
                                                duration: const Duration(
                                                  milliseconds: 300,
                                                ),
                                              ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: widget.scrollController,
                builder: (context, child) {
                  final scroll = widget.scrollController;
                  // 背景每增高一段，安全内容区的中心下移半段。
                  // 抵消一半滚动位移，让前景随拉伸居中；上滑正常滚动。
                  final correction = scroll.hasClients && !reduceMotion
                      ? math.min(0.0, scroll.offset) / 2
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(0, correction),
                    child: child,
                  );
                },
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.lg,
                      vertical: SpacingTokens.lg,
                    ),
                    child: RepaintBoundary(child: widget.child)
                        .animatePage(context)
                        .fadeIn(duration: const Duration(milliseconds: 300))
                        .slideY(
                          begin: .12,
                          end: 0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
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

/// 仅启停时通知前景，逐帧绘制交给背景和按钮各自的重绘边界。
class _HeroMotion extends InheritedWidget {
  const _HeroMotion({
    required this.animation,
    required this.active,
    required super.child,
  });

  final Animation<double> animation;
  final bool active;

  @override
  bool updateShouldNotify(_HeroMotion oldWidget) =>
      oldWidget.animation != animation || oldWidget.active != active;
}

/// 椭圆光轨以真实头像为中心，随前景移动，与背景共用启停时钟。
class HeroAvatarHalo extends StatelessWidget {
  const HeroAvatarHalo({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.dependOnInheritedWidgetOfExactType<_HeroMotion>()!;
    final colors = AnimatedHeroColors(
      Theme.of(context),
      style: AnimatedHeroStyle.starlight,
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: OverflowBox(
                minWidth: MediaQuery.sizeOf(context).width,
                maxWidth: MediaQuery.sizeOf(context).width,
                minHeight: SpacingTokens.xxl * 5,
                maxHeight: SpacingTokens.xxl * 5,
                child: RepaintBoundary(
                  key: const ValueKey('hero-avatar-orbits'),
                  child: CustomPaint(
                    painter: HeroAvatarHaloPainter(
                      base: colors.base,
                      foreground: colors.foreground,
                      glow: colors.glow,
                      motion: motion.animation,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.lg,
            vertical: SpacingTokens.md,
          ),
          child: child,
        ),
      ],
    );
  }
}

/// 每六秒轻呼吸一次，间隔四秒；与背景一起启停。
class HeroActionReminder extends StatelessWidget {
  const HeroActionReminder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = AnimatedHeroColors(Theme.of(context)).foreground;
    final motion = context.dependOnInheritedWidgetOfExactType<_HeroMotion>()!;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: motion.animation,
        child: child,
        builder: (context, child) {
          final progress = motion.animation.value;
          final pulse = motion.active && progress < 1 / 3
              ? (1 - math.cos(progress * math.pi * 6)) / 2
              : 0.0;
          return Transform.scale(
            scale: 1 + pulse * .06,
            child: ColoredCard(
              color: color,
              backgroundOpacity: 0,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(SpacingTokens.radiusPill),
              boxShadow: pulse == 0
                  ? null
                  : [
                      BoxShadow(
                        color: color.withValues(alpha: .34 * pulse),
                        blurRadius: SpacingTokens.md * pulse,
                        spreadRadius: SpacingTokens.xs * pulse,
                      ),
                    ],
              child: child!,
            ),
          );
        },
      ),
    );
  }
}

/// 连续变形的色雾与水波亮纹；网格渐变自然柔化边缘，无需离屏模糊。
class _HeroAuroraPainter extends CustomPainter {
  _HeroAuroraPainter({
    required this.base,
    required this.depth,
    required this.foreground,
    required this.glow,
    required this.pull,
    required this.motion,
  }) : super(repaint: motion);

  final Color base;
  final Color depth;
  final Color foreground;
  final Color glow;
  final double pull;
  final Animation<double> motion;

  // 背景很矮，固定网格足以平滑插值；复用缓冲区，避免逐帧创建点列表。
  static const _columns = 40;
  static const _rows = 20;
  static const _vertexCount = (_columns + 1) * (_rows + 1);
  static final _indices = Uint16List.fromList([
    for (var row = 0; row < _rows; row++)
      for (var column = 0; column < _columns; column++) ...[
        row * (_columns + 1) + column,
        (row + 1) * (_columns + 1) + column,
        row * (_columns + 1) + column + 1,
        row * (_columns + 1) + column + 1,
        (row + 1) * (_columns + 1) + column,
        (row + 1) * (_columns + 1) + column + 1,
      ],
  ]);
  final _positions = Float32List(_vertexCount * 2);
  final _colors = Int32List(_vertexCount);
  Size? _meshSize;

  late final _mist = _readable(Color.lerp(base, glow, .65)!);
  late final _crest = _readable(Color.lerp(base, foreground, .3)!);

  // 在调色时留足余量，色雾与亮纹交融也不会把文字下方叠成浅色。
  Color _readable(Color candidate) {
    final front = foreground.computeLuminance();
    double contrast(Color color) {
      final back = color.computeLuminance();
      return (math.max(front, back) + .05) / (math.min(front, back) + .05);
    }

    if (contrast(candidate) >= 5.2) return candidate;
    var low = 0.0;
    var high = 1.0;
    for (var step = 0; step < 12; step++) {
      final mix = (low + high) / 2;
      if (contrast(Color.lerp(depth, candidate, mix)!) >= 5.2) {
        low = mix;
      } else {
        high = mix;
      }
    }
    return Color.lerp(depth, candidate, low)!;
  }

  double _wave(double x, double phase) =>
      .64 +
      math.sin(x * math.pi * 1.6 - phase) * .18 +
      math.sin(x * math.pi * 3.4 + phase) * .09 -
      pull * .1;

  double _softPeak(double distance) {
    final falloff = 1 + distance * distance;
    return 1 / (falloff * falloff);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final phase = motion.value * math.pi * 2;
    if (_meshSize != size) {
      _meshSize = size;
      for (var row = 0; row <= _rows; row++) {
        for (var column = 0; column <= _columns; column++) {
          final vertex = row * (_columns + 1) + column;
          _positions[vertex * 2] = column / _columns * w;
          _positions[vertex * 2 + 1] = row / _rows * h;
        }
      }
    }

    for (var column = 0; column <= _columns; column++) {
      final x = column / _columns;
      final wave = _wave(x, phase);
      final undertow = .45 + math.cos(x * math.pi * 1.4 + phase) * .3;
      final sweep = .48 + .52 * math.pow(math.cos(x * math.pi - phase), 2);
      final focus = .58 + .42 * Curves.easeInOut.transform(x);
      for (var row = 0; row <= _rows; row++) {
        final y = row / _rows;
        final field = _softPeak((y - undertow) / .42) * focus;
        final foam = _softPeak((y - wave) / .16) * focus * sweep;
        final ground = Color.lerp(base, depth, .3 + x * .4 + y * .2)!;
        final mist = Color.lerp(ground, _mist, field * .8)!;
        _colors[row * (_columns + 1) + column] = Color.lerp(
          mist,
          _crest,
          foam * .9,
        )!.toARGB32();
      }
    }
    final mesh = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _positions,
      colors: _colors,
      indices: _indices,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawVertices(mesh, BlendMode.dst, Paint());
    mesh.dispose();

    // 亮纹铺满整个背景，左侧也保留清晰的线条，右端柔和淡出。
    for (var line = 0; line < 3; line++) {
      final path = Path();
      for (var sample = 0; sample <= 64; sample++) {
        final x = sample / 64;
        final y = _wave(x, phase + line * .2) + line * .05;
        if (sample == 0) {
          path.moveTo(x * w, y * h);
        } else {
          path.lineTo(x * w, y * h);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..shader = LinearGradient(
            colors: [
              _crest.withValues(alpha: .45 - line * .1),
              _crest.withValues(alpha: .65 - line * .15),
              _crest.withValues(alpha: .6 - line * .15),
              _crest.withValues(alpha: .18 - line * .05),
            ],
            stops: const [0, .28, .7, 1],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroAuroraPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.depth != depth ||
      oldDelegate.foreground != foreground ||
      oldDelegate.glow != glow ||
      oldDelegate.pull != pull ||
      oldDelegate.motion != motion;
}
