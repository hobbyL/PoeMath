import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 手指左划进入下一项，右划返回上一项；边界处交由外层区域处理。
///
/// 内层优先识别手势。某个方向的回调为空时，使用最近外层的对应回调，
/// 让栏目与底部 Tab 连续切换，同时避免一次手势切换两次。
class SwipeNavigationRegion extends StatefulWidget {
  const SwipeNavigationRegion({
    super.key,
    this.onNext,
    this.onPrevious,
    this.nextPageBuilder,
    this.previousPageBuilder,
    this.transitionKey,
    this.transitionDirection = 1,
    this.animateBodyOnly = false,
    required this.child,
  });

  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final WidgetBuilder? nextPageBuilder;
  final WidgetBuilder? previousPageBuilder;
  final Object? transitionKey;

  /// 页面进入时从哪一侧开始：1 从右侧进入，-1 从左侧进入。
  final double transitionDirection;

  /// 内部栏目切换时仅移动 [SwipeNavigationBody]，导航栏仍在手势区域内。
  /// 到达边界、继承外层导航时，恢复整页平移以衔接相邻主 Tab。
  final bool animateBodyOnly;
  final Widget child;

  @override
  State<SwipeNavigationRegion> createState() => _SwipeNavigationRegionState();
}

class _SwipeNavigationRegionState extends State<SwipeNavigationRegion>
    with SingleTickerProviderStateMixin {
  // 手势距离与速度阈值，不随字体或主题变化。
  static const _minSwipeDistance = 56.0;
  static const _settleDuration = Duration(milliseconds: 220);
  double _dragOffset = 0;
  double _animationStart = 0;
  double _animationEnd = 0;
  double _viewportWidth = 0;
  VoidCallback? _pendingNavigation;
  VoidCallback? _pendingInheritedNavigation;
  bool _isDragging = false;
  bool _pointerCancelled = false;
  bool _isSettlingGesture = false;
  bool _skipNextIncomingTransition = false;
  WidgetBuilder? _cachedPreviewBuilder;
  Widget? _cachedPreview;
  late final AnimationController _settleController = AnimationController(
    vsync: this,
    duration: _settleDuration,
  )..addStatusListener(_onSettleStatus);

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SwipeNavigationRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transitionKey == widget.transitionKey ||
        oldWidget.transitionKey == null) {
      return;
    }
    _settleController.stop();
    _pendingNavigation = null;
    _pendingInheritedNavigation = null;
    _isDragging = false;
    _isSettlingGesture = false;
    if (_skipNextIncomingTransition) {
      _skipNextIncomingTransition = false;
      _dragOffset = 0;
      return;
    }
    _dragOffset = widget.transitionDirection.sign * _viewportWidth;
    _animationStart = _dragOffset;
    _animationEnd = 0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _dragOffset = 0;
    } else {
      unawaited(
        _settleController.forward(from: 0).orCancel.catchError((Object _) {}),
      );
    }
  }

  void _onDescendantNavigationCommitted() {
    _skipNextIncomingTransition = true;
    _clearSkipIfTransitionDidNotHappen(widget.transitionKey);
  }

  void _clearSkipIfTransitionDidNotHappen(Object? previousKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_skipNextIncomingTransition ||
          widget.transitionKey != previousKey) {
        return;
      }
      _skipNextIncomingTransition = false;
    });
  }

  void _onDragStart() {
    _pointerCancelled = false;
    _settleController.stop();
    _pendingNavigation = null;
    _pendingInheritedNavigation = null;
    setState(() {
      _dragOffset = 0;
      _isDragging = true;
      _isSettlingGesture = false;
      _skipNextIncomingTransition = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    setState(() {
      _dragOffset = (_dragOffset + delta)
          .clamp(-_viewportWidth, _viewportWidth)
          .toDouble();
    });
  }

  void _onDragEnd(
    VoidCallback? onNext,
    VoidCallback? onPrevious, {
    VoidCallback? inheritedNextNavigation,
    VoidCallback? inheritedPreviousNavigation,
  }) {
    final offset = _dragOffset;
    final navigation = offset < 0 ? onNext : onPrevious;
    final shouldNavigate =
        offset.abs() >= _minSwipeDistance && navigation != null;
    setState(() {
      _isDragging = false;
      _isSettlingGesture = true;
      _animationStart = offset;
      _animationEnd = shouldNavigate ? offset.sign * _viewportWidth : 0;
      _pendingNavigation = shouldNavigate ? navigation : null;
      _pendingInheritedNavigation = shouldNavigate
          ? (offset < 0 ? inheritedNextNavigation : inheritedPreviousNavigation)
          : null;
    });

    if (MediaQuery.disableAnimationsOf(context)) {
      _finishSettle();
      return;
    }
    unawaited(
      _settleController.forward(from: 0).orCancel.catchError((Object _) {}),
    );
  }

  void _finishSettle() {
    final navigation = _pendingNavigation;
    final inheritedNavigation = _pendingInheritedNavigation;
    _pendingNavigation = null;
    _pendingInheritedNavigation = null;
    if (!mounted) return;
    final previousKey = widget.transitionKey;
    setState(() {
      _dragOffset = 0;
      _isDragging = false;
      _isSettlingGesture = false;
      _skipNextIncomingTransition = navigation != null;
    });
    inheritedNavigation?.call();
    navigation?.call();
    if (navigation != null) _clearSkipIfTransitionDidNotHappen(previousKey);
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finishSettle();
  }

  double _displayOffset() {
    if (!_settleController.isAnimating) return _dragOffset;
    final progress = Curves.easeOutCubic.transform(_settleController.value);
    return _animationStart + (_animationEnd - _animationStart) * progress;
  }

  Widget? _previewFor(WidgetBuilder? builder, BuildContext context) {
    if (builder == null) {
      _cachedPreviewBuilder = null;
      _cachedPreview = null;
      return null;
    }
    if (!identical(builder, _cachedPreviewBuilder)) {
      _cachedPreviewBuilder = builder;
      _cachedPreview = builder(context);
    }
    return _cachedPreview;
  }

  @override
  Widget build(BuildContext context) {
    final parent = context
        .dependOnInheritedWidgetOfExactType<_SwipeNavigationActions>();
    final onNext = widget.onNext ?? parent?.onNext;
    final onPrevious = widget.onPrevious ?? parent?.onPrevious;
    final nextPageBuilder = widget.onNext == null
        ? parent?.nextPageBuilder
        : widget.nextPageBuilder;
    final previousPageBuilder = widget.onPrevious == null
        ? parent?.previousPageBuilder
        : widget.previousPageBuilder;
    final inheritedNextNavigation = widget.onNext == null && onNext != null
        ? parent?.onNextNavigationCommitted
        : null;
    final inheritedPreviousNavigation =
        widget.onPrevious == null && onPrevious != null
        ? parent?.onPreviousNavigationCommitted
        : null;
    final descendantNextNavigation = widget.onNext != null
        ? _onDescendantNavigationCommitted
        : parent?.onNextNavigationCommitted;
    final descendantPreviousNavigation = widget.onPrevious != null
        ? _onDescendantNavigationCommitted
        : parent?.onPreviousNavigationCommitted;
    return _SwipeNavigationActions(
      onNext: onNext,
      onPrevious: onPrevious,
      nextPageBuilder: nextPageBuilder,
      previousPageBuilder: previousPageBuilder,
      onNextNavigationCommitted: descendantNextNavigation,
      onPreviousNavigationCommitted: descendantPreviousNavigation,
      child: Listener(
        // Flutter 已接受拖动后，PointerCancel 也会触发 onDragEnd。
        // 原始取消事件先经过 Listener，避免把系统取消误判为松手切页。
        onPointerCancel: (_) => _pointerCancelled = true,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // 读屏继续使用现有导航按钮与列表滚动语义。
          excludeFromSemantics: true,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => _onDragStart(),
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: (_) => _onDragEnd(
            _pointerCancelled ? null : onNext,
            _pointerCancelled ? null : onPrevious,
            inheritedNextNavigation: inheritedNextNavigation,
            inheritedPreviousNavigation: inheritedPreviousNavigation,
          ),
          onHorizontalDragCancel: () {
            if (_isDragging) _onDragEnd(null, null);
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewportWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 0;
              final displayedOffset = _displayOffset();
              final previewIsNext = displayedOffset < 0;
              final previewBuilder = !_isDragging && !_isSettlingGesture
                  ? null
                  : previewIsNext
                  ? (onNext == null ? null : nextPageBuilder)
                  : (onPrevious == null ? null : previousPageBuilder);
              final previewChild = _previewFor(previewBuilder, context);
              final usesOwnNavigation = previewIsNext
                  ? widget.onNext != null
                  : widget.onPrevious != null;
              final bodyOnly =
                  widget.animateBodyOnly &&
                  ((!_isDragging && !_isSettlingGesture) || usesOwnNavigation);
              return _SwipeBodyTransition(
                bodyOnly: bodyOnly,
                hasLocalGesture:
                    (_isDragging || _isSettlingGesture) && usesOwnNavigation,
                animation: _settleController,
                displayOffset: _displayOffset,
                viewportWidth: _viewportWidth,
                preview: previewChild,
                previewIsNext: previewIsNext,
                child: _SwipeTransitionViewport(
                  enabled: !bodyOnly,
                  animation: _settleController,
                  displayOffset: _displayOffset,
                  viewportWidth: _viewportWidth,
                  preview: previewChild,
                  previewIsNext: previewIsNext,
                  child: widget.child,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 放在子页面正文中，保留其 Scaffold/AppBar 在平移动画之外。
/// 已访问但不可见的栏目保留此节点，以免切换时重建滚动和输入状态。
class SwipeNavigationBody extends StatelessWidget {
  const SwipeNavigationBody({
    super.key,
    this.enabled = true,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final transition = context
        .dependOnInheritedWidgetOfExactType<_SwipeBodyTransition>();
    assert(
      transition != null,
      'SwipeNavigationBody requires SwipeNavigationRegion',
    );
    if (transition == null) return child;
    return _SwipeTransitionViewport(
      enabled: enabled && transition.bodyOnly,
      paintBackground: false,
      animation: transition.animation,
      displayOffset: transition.displayOffset,
      viewportWidth: transition.viewportWidth,
      preview: transition.preview,
      previewIsNext: transition.previewIsNext,
      child: child,
    );
  }
}

/// 保留分段按钮的布局与操作，让选中底色跟随内部页面的拖动和回弹。
/// 预览只参与绘制，实际选中项与无障碍状态在页面切换完成后更新。
class SwipeNavigationSegmentedButton<T> extends StatelessWidget {
  const SwipeNavigationSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.style,
  });

  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<Set<T>> onSelectionChanged;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final transition = context
        .dependOnInheritedWidgetOfExactType<_SwipeBodyTransition>();
    final theme = Theme.of(context);
    final themeStyle = SegmentedButtonTheme.of(context).style;
    final buttonStyle = (style ?? const ButtonStyle()).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        return style?.backgroundColor?.resolve(states) ??
            themeStyle?.backgroundColor?.resolve(states) ??
            (states.contains(WidgetState.selected)
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surface);
      }),
      // 手势和松手动画已提供逐帧进度，按钮不能再叠加自己的渐变延迟。
      animationDuration: Duration.zero,
    );
    final unselectedStyle = buttonStyle.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        return buttonStyle.backgroundColor!.resolve(
          {...states}..remove(WidgetState.selected),
        );
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        final unselectedStates = {...states}..remove(WidgetState.selected);
        return style?.foregroundColor?.resolve(unselectedStates) ??
            themeStyle?.foregroundColor?.resolve(unselectedStates) ??
            theme.colorScheme.onSurface;
      }),
    );

    Widget button({bool neutral = false, bool preview = false}) =>
        SegmentedButton<T>(
          showSelectedIcon: false,
          style: neutral ? unselectedStyle : buttonStyle,
          segments: segments,
          selected: preview
              ? {for (final item in segments) item.value}
              : {selected},
          multiSelectionEnabled: preview,
          onSelectionChanged: onSelectionChanged,
        );

    if (transition == null) return button();
    final selectedIndex = segments.indexWhere((item) => item.value == selected);
    return AnimatedBuilder(
      animation: transition.animation,
      // 选中层只有裁切位置随进度变化，文字和按钮不在每个动画帧重建。
      child: button(preview: true),
      builder: (context, child) {
        final offset =
            transition.hasLocalGesture && transition.viewportWidth > 0
            ? -transition.displayOffset() / transition.viewportWidth
            : 0.0;
        final targetIndex = selectedIndex + offset.sign.toInt();
        final hasTarget =
            offset != 0 && targetIndex >= 0 && targetIndex < segments.length;
        return Stack(
          children: [
            button(neutral: hasTarget),
            if (hasTarget)
              Positioned.fill(
                child: ExcludeFocus(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      // 平移选中层的可见区域，保留两套字色各自的对比度；
                      // 直接混合深浅字色会在拖动中点让文字与底色趋同。
                      child: ClipRect(
                        key: const ValueKey('swipe-navigation-selection'),
                        clipper: _SwipeSegmentClipper(
                          position: selectedIndex + offset,
                          count: segments.length,
                          textDirection: Directionality.of(context),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SwipeSegmentClipper extends CustomClipper<Rect> {
  const _SwipeSegmentClipper({
    required this.position,
    required this.count,
    required this.textDirection,
  });

  final double position;
  final int count;
  final TextDirection textDirection;

  @override
  Rect getClip(Size size) {
    final width = size.width / count;
    final index = textDirection == TextDirection.ltr
        ? position
        : count - 1 - position;
    return Rect.fromLTWH(index * width, 0, width, size.height);
  }

  @override
  bool shouldReclip(_SwipeSegmentClipper oldClipper) =>
      position != oldClipper.position ||
      count != oldClipper.count ||
      textDirection != oldClipper.textDirection;
}

class _SwipeBodyTransition extends InheritedWidget {
  const _SwipeBodyTransition({
    required this.bodyOnly,
    required this.hasLocalGesture,
    required this.animation,
    required this.displayOffset,
    required this.viewportWidth,
    required this.preview,
    required this.previewIsNext,
    required super.child,
  });

  final bool bodyOnly;
  final bool hasLocalGesture;
  final Animation<double> animation;
  final ValueGetter<double> displayOffset;
  final double viewportWidth;
  final Widget? preview;
  final bool previewIsNext;

  // 拖动进度由 State 保存；每次手势更新都要让正文读取新位移。
  @override
  bool updateShouldNotify(_SwipeBodyTransition oldWidget) => true;
}

class _SwipeTransitionViewport extends StatelessWidget {
  const _SwipeTransitionViewport({
    required this.enabled,
    this.paintBackground = true,
    required this.animation,
    required this.displayOffset,
    required this.viewportWidth,
    required this.preview,
    required this.previewIsNext,
    required this.child,
  });

  final bool enabled;
  final bool paintBackground;
  final Animation<double> animation;
  final ValueGetter<double> displayOffset;
  final double viewportWidth;
  final Widget? preview;
  final bool previewIsNext;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: ColoredBox(
      color: paintBackground
          ? Theme.of(context).scaffoldBackgroundColor
          : Colors.transparent,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final offset = enabled ? displayOffset() : 0.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (enabled && preview != null)
                Transform.translate(
                  key: ValueKey(
                    previewIsNext
                        ? 'swipe-navigation-next-preview'
                        : 'swipe-navigation-previous-preview',
                  ),
                  offset: Offset(
                    previewIsNext
                        ? viewportWidth + offset
                        : -viewportWidth + offset,
                    0,
                  ),
                  child: ExcludeFocus(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: RepaintBoundary(child: preview),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                key: const ValueKey('swipe-navigation-content'),
                offset: Offset(offset, 0),
                child: child,
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _SwipeNavigationActions extends InheritedWidget {
  const _SwipeNavigationActions({
    required this.onNext,
    required this.onPrevious,
    required this.nextPageBuilder,
    required this.previousPageBuilder,
    required this.onNextNavigationCommitted,
    required this.onPreviousNavigationCommitted,
    required super.child,
  });

  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final WidgetBuilder? nextPageBuilder;
  final WidgetBuilder? previousPageBuilder;
  final VoidCallback? onNextNavigationCommitted;
  final VoidCallback? onPreviousNavigationCommitted;

  @override
  bool updateShouldNotify(_SwipeNavigationActions oldWidget) =>
      onNext != oldWidget.onNext ||
      onPrevious != oldWidget.onPrevious ||
      nextPageBuilder != oldWidget.nextPageBuilder ||
      previousPageBuilder != oldWidget.previousPageBuilder ||
      onNextNavigationCommitted != oldWidget.onNextNavigationCommitted ||
      onPreviousNavigationCommitted != oldWidget.onPreviousNavigationCommitted;
}
