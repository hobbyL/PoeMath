// 首页打卡背景适配：打卡完成后停止动效，并固定背景标识。
import 'package:flutter/material.dart';

import 'package:poemath/core/widgets/animated_hero_header.dart';

typedef HomeCheckInColors = AnimatedHeroColors;
typedef HomeCheckInReminder = HeroActionReminder;

class HomeCheckInHeader extends AnimatedHeroHeader {
  const HomeCheckInHeader({
    super.key,
    required super.scrollController,
    required super.child,
    bool pending = true,
  }) : super(
         animate: pending,
         backgroundKey: const ValueKey('home-check-in-background'),
       );
}
