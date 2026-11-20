import 'package:flutter/material.dart';
import 'package:poemath/core/widgets/pine_ink_surface.dart';

/// 子页面的统一底图，位于正文之后、滚动区域之外。
///
/// 保留原生 Scaffold 的安全区、键盘避让、抽屉与底部操作布局。正文自行
/// 决定纸面和画布颜色；背景不叠在题目、原书图片或书写笔迹上。
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backgroundScene = PineInkScene.landscape,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
    this.endDrawer,
    this.extendBodyBehindAppBar = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final PineInkScene backgroundScene;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;
  final Widget? endDrawer;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      endDrawer: endDrawer,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      body: SizedBox.expand(
        child: PineInkSurface(scene: backgroundScene, page: true, child: body),
      ),
    );
  }
}
