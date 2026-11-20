// lib/core/theme/color_tokens.dart
//
// 层级：core/theme（设计令牌 - 颜色板）
// 职责：集中定义宣纸水墨主题、练习插画及语义色的全部颜色常量。
// 规则：所有 widget 与主题构建器 **只能** 从此文件读取颜色，禁止在业务代码中硬编码 Color(0xFF...)。

import 'package:flutter/painting.dart';

/// 颜色令牌总入口。
///
/// 通过 `ColorTokens.poemGreen` / `ColorTokens.mathPurple` 访问。
class ColorTokens {
  const ColorTokens._();

  // ============ 诗词国风水墨 ============
  /// 宣纸底：Scaffold 背景
  static const Color poemPaper = Color(0xFFF7F0E2);

  /// 素纸表面：弹窗、输入区域及底部导航。
  static const Color paperSurface = Color(0xFFFFFBF3);
  static const Color paperRaised = Color(0xFFF0E7D6);

  /// 启动水墨画的宣纸底，与图片外沿及 Android ic_launcher_background 同色。
  static const Color startupPaper = Color(0xFFF9E7C8);

  /// 宣纸深：卡片/次级背景
  static const Color poemPaperDeep = Color(0xFFE9DFCD);

  /// 墨色：主要文字
  static const Color poemInk = Color(0xFF2D352F);

  /// 淡墨：次级文字
  static const Color poemInkLight = Color(0xFF565D53);

  /// 墨绿：主色调
  static const Color poemGreen = Color(0xFF245B4E);

  /// 墨绿深：按下 / 强调
  static const Color poemGreenDeep = Color(0xFF243E32);

  /// 深色主题的墨绿前景，保持在深底及着色卡片上的可读性。
  static const Color poemGreenLight = Color(0xFFA8D4BC);

  /// 朱砂：点缀强调色
  static const Color poemCinnabar = Color(0xFF934B3D);

  static const Color poemCinnabarLight = Color(0xFFE8B4A3);

  /// 描金：装饰线 / 徽章
  static const Color poemGold = Color(0xFFC9A56A);

  /// 赭石主色；完整纸色与夜色均独立于松墨。
  static const Color inkOchre = Color(0xFF7C4028);
  static const Color inkOchreLight = Color(0xFFF0BE82);

  // 松墨：近白素宣、沉墨与松绿。绿只用于墨色，纸面保持低饱和。
  static const Color pinePaper = Color(0xFFF5F7F6);
  static const Color pineSurface = Color(0xFFFCFEFD);
  static const Color pineRaised = Color(0xFFECF0ED);
  static const Color pinePaperDeep = Color(0xFFE1E8E3);
  static const Color pineInk = Color(0xFF263A32);
  static const Color pineMutedInk = Color(0xFF58665F);
  static const Color pineRule = Color(0xFFD7E0D9);
  static const Color pineAccent = Color(0xFF4E6273);
  static const Color pineAccentLight = Color(0xFFB5CDD9);
  static const Color pineNight = Color(0xFF151F1C);
  static const Color pineNightSurface = Color(0xFF202D27);
  static const Color pineNightRaised = Color(0xFF2D3D33);
  static const Color pineNightInk = Color(0xFFE4F2E9);
  static const Color pineNightMuted = Color(0xFFAFCCC1);
  static const Color pineNightRule = Color(0xFF3C5146);

  // 赭石：暖黄旧纸、棕墨与朱砂；夜色保持赤褐基调。
  static const Color ochrePaper = Color(0xFFEDD4AC);
  static const Color ochreSurface = Color(0xFFFFF2D9);
  static const Color ochreRaised = Color(0xFFE8CCA2);
  static const Color ochrePaperDeep = Color(0xFFDFC095);
  static const Color ochreInk = Color(0xFF422B20);
  static const Color ochreMutedInk = Color(0xFF694A37);
  static const Color ochreRule = Color(0xFFC0A077);
  static const Color ochreAccent = Color(0xFF705126);
  static const Color ochreAccentLight = Color(0xFFE2C58D);
  static const Color ochreNight = Color(0xFF322118);
  static const Color ochreNightSurface = Color(0xFF493124);
  static const Color ochreNightRaised = Color(0xFF604332);
  static const Color ochreNightInk = Color(0xFFFFF0D5);
  static const Color ochreNightMuted = Color(0xFFD7BFA0);
  static const Color ochreNightRule = Color(0xFF88674C);
  static const Color ochreSeal = Color(0xFF8C372A);
  static const Color ochreSealLight = Color(0xFFF0AF91);
  static const Color ochreCaution = Color(0xFF69451E);
  static const Color ochreSuccess = Color(0xFF24542D);

  // 奶糖乐园：柔粉与莓果，青薄荷和葡萄紫作点缀。
  static const Color candyPage = Color(0xFFFFF0F6);
  static const Color candySurface = Color(0xFFFFFAFD);
  static const Color candyRaised = Color(0xFFF8DDEB);
  static const Color candyPrimary = Color(0xFF9B345E);
  static const Color candySecondary = Color(0xFF376553);
  static const Color candyTertiary = Color(0xFF6E4595);
  static const Color candyInk = Color(0xFF30192A);
  static const Color candyMuted = Color(0xFF765469);
  static const Color candyRule = Color(0xFFE8BED1);
  static const Color candyNight = Color(0xFF2C1D30);
  static const Color candyNightSurface = Color(0xFF3D2A43);
  static const Color candyNightRaised = Color(0xFF503657);
  static const Color candyNightInk = Color(0xFFFFECF6);
  static const Color candyNightMuted = Color(0xFFDAB7D0);
  static const Color candyNightRule = Color(0xFF71506A);
  static const Color candyPrimaryLight = Color(0xFFFFB3D3);
  static const Color candySecondaryLight = Color(0xFFA6DEC8);
  static const Color candyTertiaryLight = Color(0xFFD8BBFF);

  // 星海探险：天空蓝、星光金与紫罗兰，夜间保留深蓝天幕。
  static const Color spacePage = Color(0xFFE8F3FF);
  static const Color spaceSurface = Color(0xFFF9FCFF);
  static const Color spaceRaised = Color(0xFFD9E9FC);
  static const Color spacePrimary = Color(0xFF2558A5);
  static const Color spaceSecondary = Color(0xFF7B5100);
  static const Color spaceTertiary = Color(0xFF6648A3);
  static const Color spaceInk = Color(0xFF11253F);
  static const Color spaceMuted = Color(0xFF4D627F);
  static const Color spaceRule = Color(0xFFB4D1EF);
  static const Color spaceNight = Color(0xFF101F3B);
  static const Color spaceNightSurface = Color(0xFF1D3153);
  static const Color spaceNightRaised = Color(0xFF2B4267);
  static const Color spaceNightInk = Color(0xFFE9F3FF);
  static const Color spaceNightMuted = Color(0xFFB4C9E5);
  static const Color spaceNightRule = Color(0xFF47668C);
  static const Color spacePrimaryLight = Color(0xFFA8CEFF);
  static const Color spaceSecondaryLight = Color(0xFFFFE096);
  static const Color spaceTertiaryLight = Color(0xFFC9BEFF);

  /// 印章红：勋章 / 收藏标记
  static const Color poemSeal = Color(0xFFA83E3E);

  /// 淡宣纸分割线
  static const Color poemDivider = Color(0xFFDCD5C6);

  // ============ 练习插画色（不再作为独立主题） ============
  /// 温白底：Scaffold 背景
  static const Color mathBackground = poemPaper;

  /// 素纸 Surface：卡片
  static const Color mathSurface = paperSurface;

  /// 薰衣草紫：主色
  static const Color mathPurple = Color(0xFFB5A0E8);

  /// 薰衣草紫深：文字/强调（满足 WCAG 对比度）
  static const Color mathPurpleDeep = Color(0xFF6B52B5);

  /// 奶油黄：次要色 / 高亮
  static const Color mathYellow = Color(0xFFFFD98A);

  /// 樱花粉：装饰 / 女孩向
  static const Color mathPink = Color(0xFFFFB1C1);

  /// 浅色主题中可承载白字、也可用于文字的樱花色。
  static const Color mathPinkDeep = Color(0xFF963F64);

  /// 冰川蓝：进度 / 信息
  static const Color mathBlue = Color(0xFF9FD3E8);

  /// 薄荷绿：答对
  static const Color mathMint = Color(0xFFA8E6C9);

  /// 珊瑚：答错 / 强调
  static const Color mathCoral = Color(0xFFFF9A8B);

  /// 口算主文字色
  static const Color mathTextDark = poemInk;

  /// 口算次级文字色
  static const Color mathTextLight = poemInkLight;

  // ============ 语义色（跨主题共享） ============
  static const Color success = Color(0xFF52C41A);
  static const Color warning = Color(0xFFFAAD14);
  static const Color error = Color(0xFFFF4D4F);
  static const Color info = Color(0xFF1890FF);

  /// 信息文字使用的浅色主题前景；装饰色仍使用上方原始调色板。
  static const Color successText = Color(0xFF256735);
  static const Color cautionText = Color(0xFF795517);

  /// 庆祝光晕/插画的原始装饰色；标题使用主题语义前景。
  static const Color celebrationCheckIn = Color(0xFF4CAF50);
  static const Color celebrationAchievement = Color(0xFFFFC107);
  static const Color celebrationLevelUp = Color(0xFF2196F3);

  /// 提示灯亮起时的琥珀色，在浅色图片上保留清晰轮廓。
  static const Color hintAmber = Color(0xFF9A6700);

  // ============ 深色模式：夜墨底与暖纸文字 ============
  /// 深色背景
  static const Color darkBackground = Color(0xFF1D2521);

  /// 深色卡片 Surface
  static const Color darkSurface = Color(0xFF27312B);

  /// 深色主文字
  static const Color darkTextPrimary = Color(0xFFF0E8DA);
  static const Color darkTextSecondary = Color(0xFFC4C9BC);
}
