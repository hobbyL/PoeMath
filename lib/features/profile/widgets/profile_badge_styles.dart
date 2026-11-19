import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/animated_hero_header.dart';
import 'package:poemath/domain/level_calculator.dart';

/// 成长状态只决定展示，不写入奖励或另设一套升级门槛。
class ProfileBadgeStyles {
  const ProfileBadgeStyles._();

  // 童生、秀才、举人、进士、探花、榜眼、状元、诗仙。
  static const _levelColors = [
    (ColorTokens.poemGreenLight, ColorTokens.inkOchreLight),
    (ColorTokens.mathMint, ColorTokens.poemGreenLight),
    (ColorTokens.mathMint, ColorTokens.poemGold),
    (ColorTokens.inkOchreLight, ColorTokens.poemCinnabarLight),
    (ColorTokens.poemCinnabarLight, ColorTokens.poemGold),
    (ColorTokens.poemGold, ColorTokens.inkOchreLight),
    (ColorTokens.poemCinnabarLight, ColorTokens.inkOchreLight),
    (ColorTokens.inkOchreLight, ColorTokens.poemGreenLight),
  ];

  static HeroTagStyle level(int level) {
    final rank = level.clamp(0, _levelColors.length - 1);
    final (accent, secondaryAccent) = _levelColors[rank];
    return HeroTagStyle(
      accent: accent,
      secondaryAccent: secondaryAccent,
      emphasis: rank / (_levelColors.length - 1),
      trailCount: rank >= 3 ? 2 : 1,
      sparkleCount: switch (rank) {
        7 => 3,
        6 => 2,
        _ => 0,
      },
    );
  }

  static HeroTagStyle stars(int totalStars) {
    // 50 / 300 / 800 / 2000 星对应既有秀才 / 进士 / 榜眼 / 诗仙门槛。
    final milestone = switch (LevelCalculator.calculate(totalStars)) {
      >= 7 => 4,
      >= 5 => 3,
      >= 3 => 2,
      >= 1 => 1,
      _ => 0,
    };
    return HeroTagStyle(
      accent: ColorTokens.inkOchreLight,
      secondaryAccent: ColorTokens.poemGold,
      emphasis: milestone / 4,
      trailCount: milestone >= 3 ? 2 : 1,
      sparkleCount: milestone,
    );
  }
}
